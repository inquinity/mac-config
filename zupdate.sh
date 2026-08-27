#!/usr/bin/env bash
#
# zupdate.sh - Compare the dotfiles tracked in this repo against the live
#              copies in $HOME and, on request, sync the newer copy in either
#              direction.
#
# With no arguments this is read-only: it prints a status report and exits.
# Copying only ever happens when --update is passed.
#
# A hard-coded control list below decides which files are managed, so nothing
# is picked up by accident (notably the machine-specific .*-uhg files).
#
# Some settings must differ between the two copies, or must be normalized on
# the way through. Those are enforced by the policy filter rather than copied
# verbatim -- see GIT_EMAIL_HOME / GIT_EMAIL_CONFIG and the excludesfile rule.

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_DIM="\e[2m"            # Used for secondary detail such as timestamps
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Honor NO_COLOR and non-terminal output (pipes, files, CI).
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    COLOR_GREEN="" COLOR_RED="" COLOR_YELLOW="" COLOR_CYAN=""
    COLOR_BRIGHTYELLOW="" COLOR_DIM="" COLOR_RESET=""
fi

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf '%b%s%b\n' "$color" "$message" "$COLOR_RESET"
}

# ---------------------------------------------------------------------------
# Control list: the only files this script will ever read, compare, or write.
#
# Deliberately excluded:
#   .*-uhg    machine/employer-specific overrides that must never be shared
#   .emacs.d  a directory tree; use copy-here.sh for that
# ---------------------------------------------------------------------------
MANAGED_DOTFILES=(
    .zshenv
    .zshrc
    .zprofile
    .zlogin
    .gitconfig
    .gitignore
    .gitignore_global
)

# ---------------------------------------------------------------------------
# Policy: values that are intentionally different per side, or normalized.
#
#   .gitconfig [user] email       work address in $HOME, personal in the repo
#                                 (the inactive address is kept as a comment)
#   .gitconfig [core] excludesfile rewritten to ~/... so no username is baked in
#
# Because the email differs by design, comparison is done on a canonical form
# in which both addresses are replaced by MANAGED_PLACEHOLDER. That way the two
# copies still register as "same" when only the managed lines differ.
# ---------------------------------------------------------------------------
GIT_EMAIL_HOME="robert.altman@optum.com"
GIT_EMAIL_CONFIG="robert@AltmanSoftwareDesign.com"
MANAGED_PLACEHOLDER="@@managed-by-zupdate@@"

# Globals
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dotfiles_dir="$script_dir/dotfiles"
home_dir="$HOME"
update_target=""      # "" (report only) | home | config | all
dry_run=false
show_diffs=false
temp_file=""

# Remove any half-written temp file if we exit early.
cleanup() {
    [[ -n "$temp_file" && -e "$temp_file" ]] && rm -f "$temp_file"
    return 0
}
trap cleanup EXIT INT TERM

usage() {
    cat <<'USAGE'
zupdate.sh - compare and sync tracked dotfiles between $HOME and this repo

Usage:
  zupdate.sh                    Report differences only (read-only, default)
  zupdate.sh --update home      Copy newer repo dotfiles into $HOME
  zupdate.sh --update config    Copy newer $HOME dotfiles into the repo
  zupdate.sh --update all       Sync both directions, newer copy always wins

Options:
  -u, --update <target>   One of: home, config, all
  -n, --dry-run           Show what --update would do without writing anything
  -d, --diff              Show the unified diff for each file that differs
  -h, --help              Show this help text

Status meanings:
  same            contents match, ignoring the managed settings listed below
  home newer      contents differ; the $HOME copy was modified most recently
  repo newer      contents differ; the dotfiles/ copy was modified most recently
  differs         contents differ but both have the same modification time,
                  so neither side can be called newer -- resolve by hand
  home missing    tracked in dotfiles/ but absent from $HOME
  repo missing    present in $HOME but absent from dotfiles/

Managed settings (enforced on write, ignored when comparing):
  .gitconfig  [user] email         robert.altman@optum.com in $HOME
                                   robert@AltmanSoftwareDesign.com in the repo
  .gitconfig  [core] excludesfile  rewritten to ~/... so no username is baked in

Only the files in the hard-coded control list are touched; .*-uhg files and
.emacs.d are never read or written by this script.
USAGE
}

# Modification time in epoch seconds; BSD stat first, GNU stat as fallback.
file_mtime() {
    local target_path=$1
    stat -f %m "$target_path" 2>/dev/null || stat -c %Y "$target_path"
}

# Human-readable modification time for the detail column.
file_mtime_human() {
    local target_path=$1
    stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$target_path" 2>/dev/null \
        || date -r "$(file_mtime "$target_path")" '+%Y-%m-%d %H:%M'
}

# File mode as an octal string, for preserving permissions on write.
file_mode() {
    local target_path=$1
    stat -f '%Lp' "$target_path" 2>/dev/null || stat -c '%a' "$target_path"
}

# Print one report row: glyph, status label, filename, optional detail.
print_row() {
    local color=$1 glyph=$2 status=$3 filename=$4 detail=${5:-}
    printf '  %b%s %-13s%b %-20s %b%s%b\n' \
        "$color" "$glyph" "$status" "$COLOR_RESET" \
        "$filename" \
        "$COLOR_DIM" "$detail" "$COLOR_RESET"
}

# Apply the .gitconfig policy to stdin, writing the result to stdout.
#
#   $1  address for the active   "email =" line
#   $2  address for the commented "#email =" line
#
# Both the active and commented email lines in [user] are rewritten so the two
# copies stay structurally identical and only the addresses swap.
gitconfig_policy_filter() {
    local active_email=$1
    local inactive_email=$2

    awk -v active_email="$active_email" \
        -v inactive_email="$inactive_email" \
        -v home_dir="$home_dir" '
        # Track the section so email/excludesfile rules only fire where meant.
        /^[[:space:]]*\[/ {
            section = $0
            sub(/^[[:space:]]+/, "", section)
            print
            next
        }

        # Capture leading whitespace so the original indentation survives.
        function indent_of(line,   prefix) {
            prefix = line
            sub(/[^[:space:]].*$/, "", prefix)
            return prefix
        }

        # Commented-out address is checked first so it is not caught by the
        # active-address rule below.
        section ~ /^\[user\]/ && /^[[:space:]]*#[[:space:]]*email[[:space:]]*=/ {
            print indent_of($0) "#email = " inactive_email
            next
        }

        section ~ /^\[user\]/ && /^[[:space:]]*email[[:space:]]*=/ {
            print indent_of($0) "email = " active_email
            next
        }

        # Replace an absolute home path with ~ so the value stays portable.
        # The current $HOME is handled first; the /Users/<name>/ fallback also
        # catches paths left behind by a different account.
        section ~ /^\[core\]/ && /^[[:space:]]*excludesfile[[:space:]]*=/ {
            line = $0
            home_at = index(line, home_dir "/")
            if (home_at > 0) {
                line = substr(line, 1, home_at - 1) "~/" \
                       substr(line, home_at + length(home_dir) + 1)
            } else {
                sub(/\/Users\/[^\/[:space:]]+\//, "~/", line)
            }
            print line
            next
        }

        { print }
    '
}

# Apply the policy for a given file and side to stdin -> stdout.
# Files with no policy pass through untouched.
#
#   $1  filename (e.g. .gitconfig)
#   $2  side: home | config | canonical
apply_policy() {
    local filename=$1
    local side=$2

    case $filename in
        .gitconfig)
            case $side in
                home)      gitconfig_policy_filter "$GIT_EMAIL_HOME" "$GIT_EMAIL_CONFIG" ;;
                config)    gitconfig_policy_filter "$GIT_EMAIL_CONFIG" "$GIT_EMAIL_HOME" ;;
                canonical) gitconfig_policy_filter "$MANAGED_PLACEHOLDER" "$MANAGED_PLACEHOLDER" ;;
                *)         cat ;;
            esac
            ;;
        *)
            cat
            ;;
    esac
}

# True when the two copies differ once the managed settings are neutralized.
content_differs() {
    local repo_path=$1 home_path=$2 filename=$3
    ! diff -q \
        <(apply_policy "$filename" canonical <"$repo_path") \
        <(apply_policy "$filename" canonical <"$home_path") \
        >/dev/null 2>&1
}

# True when a file does not already satisfy the policy for its side.
policy_pending() {
    local target_path=$1 filename=$2 side=$3
    ! apply_policy "$filename" "$side" <"$target_path" \
        | diff -q - "$target_path" >/dev/null 2>&1
}

# Write $1 to $2 with the policy for $4 applied, preserving permissions.
# Honors --dry-run. Writes via a temp file so a failure cannot truncate the
# destination.
write_with_policy() {
    local source_path=$1 dest_path=$2 filename=$3 side=$4
    local dest_dir preserve_mode

    if [[ $dry_run == true ]]; then
        return 0
    fi

    dest_dir=$(dirname -- "$dest_path")
    # Keep the destination's own permissions when it already exists; otherwise
    # inherit the source's.
    if [[ -e "$dest_path" ]]; then
        preserve_mode=$(file_mode "$dest_path")
    else
        preserve_mode=$(file_mode "$source_path")
    fi

    temp_file=$(mktemp "$dest_dir/.zupdate.XXXXXX")
    apply_policy "$filename" "$side" <"$source_path" >"$temp_file"
    chmod "$preserve_mode" "$temp_file"
    mv -f "$temp_file" "$dest_path"
    temp_file=""
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--update)
            if [[ $# -lt 2 ]]; then
                print_colored "$COLOR_RED" "Error: --update requires a target (home, config, or all)"
                exit 2
            fi
            update_target=$2
            shift
            ;;
        --update=*)
            update_target=${1#--update=}
            ;;
        -n|--dry-run) dry_run=true ;;
        -d|--diff)    show_diffs=true ;;
        -h|--help)    usage; exit 0 ;;
        *)
            print_colored "$COLOR_RED" "Unknown option: $1"
            printf '\n'
            usage
            exit 2
            ;;
    esac
    shift
done

# Validation
case $update_target in
    ""|home|config|all) ;;
    *)
        print_colored "$COLOR_RED" "Error: invalid --update target '$update_target' (expected home, config, or all)"
        exit 2
        ;;
esac

if [[ $dry_run == true && -z $update_target ]]; then
    print_colored "$COLOR_YELLOW" "Note: --dry-run has no effect without --update; this script is read-only by default."
    printf '\n'
fi

if [[ ! -d "$repo_dotfiles_dir" ]]; then
    print_colored "$COLOR_RED" "Error: dotfiles directory not found: $repo_dotfiles_dir"
    exit 1
fi

# Should the given direction be written this run?
may_write_home() { [[ $update_target == home || $update_target == all ]]; }
may_write_config() { [[ $update_target == config || $update_target == all ]]; }

# ---------------------------------------------------------------------------
# Pass 1: compare and report
# ---------------------------------------------------------------------------
print_colored "$COLOR_CYAN" "Comparing dotfiles"
printf '%b  home: %s\n  repo: %s%b\n\n' \
    "$COLOR_DIM" "$home_dir" "$repo_dotfiles_dir" "$COLOR_RESET"

count_same=0
count_home_newer=0
count_repo_newer=0
count_conflict=0
count_missing=0

# Parallel arrays of work for pass 2; bash 3.2 has no associative arrays.
action_files=()
action_kinds=()     # copy-to-home | copy-to-config | conflict
action_reasons=()   # why the action was queued, shown when it has to be skipped

for filename in "${MANAGED_DOTFILES[@]}"; do
    repo_path="$repo_dotfiles_dir/$filename"
    home_path="$home_dir/$filename"

    if [[ ! -e "$repo_path" && ! -e "$home_path" ]]; then
        continue    # tracked in the control list but not present anywhere yet
    fi

    if [[ ! -e "$home_path" ]]; then
        count_missing=$((count_missing + 1))
        print_row "$COLOR_RED" "?" "home missing" "$filename" "tracked but not present in \$HOME"
        action_files+=("$filename"); action_kinds+=("copy-to-home")
        action_reasons+=("absent from \$HOME")
        continue
    fi

    if [[ ! -e "$repo_path" ]]; then
        count_missing=$((count_missing + 1))
        print_row "$COLOR_RED" "?" "repo missing" "$filename" "present in \$HOME but not tracked"
        action_files+=("$filename"); action_kinds+=("copy-to-config")
        action_reasons+=("not tracked in dotfiles/")
        continue
    fi

    if ! content_differs "$repo_path" "$home_path" "$filename"; then
        count_same=$((count_same + 1))
        print_row "$COLOR_GREEN" "=" "same" "$filename"
        continue
    fi

    home_mtime=$(file_mtime "$home_path")
    repo_mtime=$(file_mtime "$repo_path")
    mtime_detail="home $(file_mtime_human "$home_path")  |  repo $(file_mtime_human "$repo_path")"

    if [[ $home_mtime -gt $repo_mtime ]]; then
        count_home_newer=$((count_home_newer + 1))
        print_row "$COLOR_BRIGHTYELLOW" ">" "home newer" "$filename" "$mtime_detail"
        action_files+=("$filename"); action_kinds+=("copy-to-config")
        action_reasons+=("home copy is newer")
    elif [[ $repo_mtime -gt $home_mtime ]]; then
        count_repo_newer=$((count_repo_newer + 1))
        print_row "$COLOR_BRIGHTYELLOW" "<" "repo newer" "$filename" "$mtime_detail"
        action_files+=("$filename"); action_kinds+=("copy-to-home")
        action_reasons+=("repo copy is newer")
    else
        count_conflict=$((count_conflict + 1))
        print_row "$COLOR_RED" "!" "differs" "$filename" "same timestamp, different contents"
        action_files+=("$filename"); action_kinds+=("conflict")
        action_reasons+=("same timestamp both sides")
    fi

    if [[ $show_diffs == true ]]; then
        printf '\n'
        print_colored "$COLOR_YELLOW" "    --- diff $filename (repo -> home, managed settings normalized) ---"
        # -L keeps the process-substitution paths out of the diff header.
        diff -u -L "repo/$filename" -L "home/$filename" \
            <(apply_policy "$filename" canonical <"$repo_path") \
            <(apply_policy "$filename" canonical <"$home_path") \
            | sed 's/^/    /' || true
        printf '\n'
    fi
done

printf '\n'
print_colored "$COLOR_CYAN" "Summary"
printf '  %b%d in sync%b, %b%d home newer%b, %b%d repo newer%b, %b%d conflicting%b, %b%d missing%b\n' \
    "$COLOR_GREEN" "$count_same" "$COLOR_RESET" \
    "$COLOR_BRIGHTYELLOW" "$count_home_newer" "$COLOR_RESET" \
    "$COLOR_BRIGHTYELLOW" "$count_repo_newer" "$COLOR_RESET" \
    "$COLOR_RED" "$count_conflict" "$COLOR_RESET" \
    "$COLOR_RED" "$count_missing" "$COLOR_RESET"

# ---------------------------------------------------------------------------
# Report only: suggest next steps and stop without writing anything.
# ---------------------------------------------------------------------------
if [[ -z $update_target ]]; then
    # Managed settings can drift even when the two copies are otherwise in
    # sync, so check both sides and mention any pending fixups.
    policy_notes=()
    for filename in "${MANAGED_DOTFILES[@]}"; do
        if [[ -e "$home_dir/$filename" ]] && policy_pending "$home_dir/$filename" "$filename" home; then
            policy_notes+=("home/$filename")
        fi
        if [[ -e "$repo_dotfiles_dir/$filename" ]] && policy_pending "$repo_dotfiles_dir/$filename" "$filename" config; then
            policy_notes+=("repo/$filename")
        fi
    done

    if [[ ${#policy_notes[@]} -gt 0 ]]; then
        printf '\n'
        print_colored "$COLOR_BRIGHTYELLOW" "Managed settings need fixing up in: ${policy_notes[*]}"
    fi

    total_pending=$((count_home_newer + count_repo_newer + count_conflict + count_missing + ${#policy_notes[@]}))
    if [[ $total_pending -eq 0 ]]; then
        printf '\n'
        print_colored "$COLOR_GREEN" "Everything is in sync."
        exit 0
    fi

    printf '\n'
    print_colored "$COLOR_GREEN" "To sync:  ./zupdate.sh --update all        (or: --update home | --update config)"
    print_colored "$COLOR_GREEN" "Preview:  ./zupdate.sh --update all -n"
    exit 1
fi

# ---------------------------------------------------------------------------
# Pass 2: apply updates
# ---------------------------------------------------------------------------
printf '\n'
if [[ $dry_run == true ]]; then
    print_colored "$COLOR_CYAN" "Updating '$update_target' (dry run -- nothing will be written)"
else
    print_colored "$COLOR_CYAN" "Updating '$update_target'"
fi
printf '\n'

changes_made=0
changes_skipped=0

for action_index in $(seq 0 $(( ${#action_files[@]} - 1 )) ); do
    # seq emits nothing useful when there are no actions; guard on the count.
    [[ ${#action_files[@]} -eq 0 ]] && break

    filename=${action_files[$action_index]}
    action_kind=${action_kinds[$action_index]}
    action_reason=${action_reasons[$action_index]}
    repo_path="$repo_dotfiles_dir/$filename"
    home_path="$home_dir/$filename"

    case $action_kind in
        copy-to-home)
            if may_write_home; then
                write_with_policy "$repo_path" "$home_path" "$filename" home
                changes_made=$((changes_made + 1))
                print_row "$COLOR_GREEN" "+" "repo -> home" "$filename" "$action_reason"
            else
                changes_skipped=$((changes_skipped + 1))
                print_row "$COLOR_DIM" "." "skipped" "$filename" "$action_reason; needs --update home"
            fi
            ;;
        copy-to-config)
            if may_write_config; then
                write_with_policy "$home_path" "$repo_path" "$filename" config
                changes_made=$((changes_made + 1))
                print_row "$COLOR_GREEN" "+" "home -> repo" "$filename" "$action_reason"
            else
                changes_skipped=$((changes_skipped + 1))
                print_row "$COLOR_DIM" "." "skipped" "$filename" "$action_reason; needs --update config"
            fi
            ;;
        conflict)
            changes_skipped=$((changes_skipped + 1))
            print_row "$COLOR_RED" "!" "skipped" "$filename" "$action_reason; resolve by hand"
            ;;
    esac
done

# Managed settings are enforced even when no copy was needed, so a stale value
# such as an absolute excludesfile path still gets corrected.
for filename in "${MANAGED_DOTFILES[@]}"; do
    if may_write_home && [[ -e "$home_dir/$filename" ]] \
        && policy_pending "$home_dir/$filename" "$filename" home; then
        write_with_policy "$home_dir/$filename" "$home_dir/$filename" "$filename" home
        changes_made=$((changes_made + 1))
        print_row "$COLOR_GREEN" "*" "fixed policy" "$filename" "in \$HOME"
    fi
    if may_write_config && [[ -e "$repo_dotfiles_dir/$filename" ]] \
        && policy_pending "$repo_dotfiles_dir/$filename" "$filename" config; then
        write_with_policy "$repo_dotfiles_dir/$filename" "$repo_dotfiles_dir/$filename" "$filename" config
        changes_made=$((changes_made + 1))
        print_row "$COLOR_GREEN" "*" "fixed policy" "$filename" "in dotfiles/"
    fi
done

printf '\n'
if [[ $changes_made -eq 0 && $changes_skipped -eq 0 ]]; then
    print_colored "$COLOR_GREEN" "Nothing to do; already in sync."
elif [[ $dry_run == true ]]; then
    print_colored "$COLOR_BRIGHTYELLOW" "Dry run: $changes_made change(s) would be made, $changes_skipped skipped."
    print_colored "$COLOR_GREEN" "Re-run without --dry-run to apply."
else
    print_colored "$COLOR_GREEN" "Done: $changes_made change(s) applied, $changes_skipped skipped."
fi
