#!/usr/bin/env bash
#
# link-dotfiles.sh - Symlink the dotfiles in this repo into $HOME.
#
# The files under dotfiles/ are stored without their leading dot so they are
# visible in ls and Finder. This script is the only place the dot is added
# back: each entry in LINKS maps a repo file to the name it has in $HOME.
#
# Machine-specific git settings (email, commit signing) live in
# dotfiles/gitconfig.home and dotfiles/gitconfig.work. The shared gitconfig
# includes ~/.gitconfig.local, and this script points that name at the file
# for this computer. A corporate computer (short name starting with LAMU)
# gets the work file; any other computer gets the home file.
#
# Existing files are never overwritten silently: a real file that differs
# from the repo copy is left alone unless --force is given.

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Honor NO_COLOR and non-terminal output (pipes, files, CI).
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    COLOR_GREEN="" COLOR_RED="" COLOR_YELLOW="" COLOR_BRIGHTYELLOW="" COLOR_RESET=""
fi

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf '%b%s%b\n' "$color" "$message" "$COLOR_RESET"
}

# Repo file (under dotfiles/) and the name it takes in $HOME.
LINKS=(
    "gitconfig:.gitconfig"
    "gitignore_global:.gitignore_global"
    "zshenv:.zshenv"
    "zshrc:.zshrc"
    "zprofile:.zprofile"
    "zlogin:.zlogin"
)

CORPORATE_NAME_PREFIX="LAMU"
LOCAL_LINK_NAME=".gitconfig.local"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dotfiles_dir="$script_dir/dotfiles"
dry_run=false
force=false
profile=""          # home | work; detected from the hostname unless given
problem_count=0

usage() {
    print_colored "$COLOR_YELLOW" "link-dotfiles.sh - symlink dotfiles from this repo into \$HOME"
    cat <<'USAGE'

Usage:
  link-dotfiles.sh [options]

Options:
  -n, --dry-run        Show what would change without changing anything
  -f, --force          Replace existing files that differ from the repo copy
      --profile NAME   Use home or work instead of detecting from hostname
  -h, --help           Show this help
USAGE
}

# Short machine name, with any domain suffix stripped.
computer_name() {
    local raw_name
    raw_name=$(hostname -s 2>/dev/null || uname -n)
    printf '%s' "${raw_name%%.*}"
}

# True when the name begins with CORPORATE_NAME_PREFIX (case-insensitive;
# macOS ships bash 3.2, which has no ${var,,}).
is_corporate_computer() {
    local lowered_name lowered_prefix
    lowered_name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    lowered_prefix=$(printf '%s' "$CORPORATE_NAME_PREFIX" | tr '[:upper:]' '[:lower:]')
    [[ $lowered_name == "$lowered_prefix"* ]]
}

report_problem() {
    print_colored "$COLOR_RED" "  $1"
    problem_count=$((problem_count + 1))
}

# Create or replace one symlink, following the safety rules in the header.
link_one() {
    local source_path=$1
    local link_path=$2
    local reason=""

    if [[ ! -e "$source_path" ]]; then
        report_problem "missing repo file: $source_path"
        return 0
    fi

    if [[ -L "$link_path" ]]; then
        # -ef compares the files the paths resolve to, so a relative link or a
        # different spelling of the same path (symlinked $HOME or repo) is fine.
        if [[ "$link_path" -ef "$source_path" ]]; then
            print_colored "$COLOR_GREEN" "  ok        $link_path"
            return 0
        fi
        reason="points elsewhere: $(readlink "$link_path")"
    elif [[ -e "$link_path" ]]; then
        if cmp -s "$source_path" "$link_path"; then
            reason="identical copy"
        else
            reason="differs from repo"
        fi
    fi

    # Anything that already exists and is not just an identical copy needs --force.
    if [[ -n "$reason" && "$reason" != "identical copy" && "$force" == false ]]; then
        report_problem "$link_path $reason; not replaced (re-run with --force after checking it)"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  would link ${link_path} -> ${source_path}${reason:+ ($reason)}"
        return 0
    fi

    ln -sfn "$source_path" "$link_path"
    print_colored "$COLOR_BRIGHTYELLOW" "  linked    ${link_path} -> ${source_path}${reason:+ ($reason)}"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run) dry_run=true ;;
        -f|--force) force=true ;;
        --profile)
            [[ $# -ge 2 ]] || { print_colored "$COLOR_RED" "--profile needs a value"; exit 2; }
            profile=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

if [[ -z "$profile" ]]; then
    if is_corporate_computer "$(computer_name)"; then profile=work; else profile=home; fi
fi
case $profile in
    home|work) ;;
    *) print_colored "$COLOR_RED" "Unknown profile '$profile' (expected home or work)"; exit 2 ;;
esac

print_colored "$COLOR_YELLOW" "Profile: $profile ($(computer_name))"
[[ "$dry_run" == true ]] && print_colored "$COLOR_YELLOW" "Dry run: no changes will be made"

for link_entry in "${LINKS[@]}"; do
    link_one "$repo_dotfiles_dir/${link_entry%%:*}" "$HOME/${link_entry#*:}"
done
link_one "$repo_dotfiles_dir/gitconfig.$profile" "$HOME/$LOCAL_LINK_NAME"

if [[ $problem_count -gt 0 ]]; then
    print_colored "$COLOR_RED" "$problem_count problem(s); see above"
    exit 1
fi
print_colored "$COLOR_GREEN" "Done"
