#!/bin/zsh

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

PROGRAM_NAME="${0:t}"
ASSUME_YES=false
DRY_RUN=false
INCLUDE_APPROVED=false

typeset -a MATCH_PATTERNS
typeset -a EXTRA_SCAN_ROOTS
typeset -a ARTIFACT_ROOTS
typeset -a ARTIFACT_TYPES
typeset -a FINDING_ROOTS
typeset -a FINDING_TYPES
typeset -a FINDING_NAMES
typeset -a FINDING_VERSIONS
typeset -a FINDING_COUNTS
typeset -a FINDING_PATHS
typeset -a FINDING_FIX_TARGETS
typeset -a FINDING_FLAGS    # quarantine flag integer per finding
typeset -a FINDING_CLASSES  # "blocking", "approved", or "hard_approved" per finding
typeset -A SEEN_ROOTS

usage() {
    cat <<EOF
Usage: ${PROGRAM_NAME} [options]

Scan Homebrew artifacts for com.apple.quarantine, show what is affected,
and optionally remove the attribute from only the affected artifact roots.

On macOS 26+, Gatekeeper sets QTN_FLAG_HARD (0x0040) on quarantine after
approving an app. These apps work normally; their quarantine is a protected
historical record that cannot be removed via xattr. The script skips them
by default and reports them as informational.

Options:
  -y, --yes              Fix findings without prompting
  -n, --dry-run          Show findings but do not change anything
  -a, --include-approved Show Gatekeeper-approved quarantine (informational);
                         attempt removal for non-HARD approved quarantine
  -m, --match PATTERN    Only include artifact names or paths matching PATTERN
  -p, --path PATH        Scan an extra artifact root outside Cellar/Caskroom
  -h, --help             Show this help text

Examples:
  ${PROGRAM_NAME}
  ${PROGRAM_NAME} --dry-run
  ${PROGRAM_NAME} --include-approved
  ${PROGRAM_NAME} --match 'codex|codeql|openjdk'
EOF
}

die() {
    print_colored "$COLOR_RED" "ERROR: $1"
    exit 1
}

info() {
    print_colored "$COLOR_YELLOW" "$1"
}

success() {
    print_colored "$COLOR_GREEN" "$1"
}

highlight() {
    print_colored "$COLOR_BRIGHTYELLOW" "$1"
}

require_command() {
    local command_name=$1
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes|--no-confirm)
                ASSUME_YES=true
                ;;
            -n|--dry-run)
                DRY_RUN=true
                ;;
            -a|--include-approved)
                INCLUDE_APPROVED=true
                ;;
            -m|--match)
                [[ $# -ge 2 ]] || die "--match requires a value"
                MATCH_PATTERNS+=("$2")
                shift
                ;;
            -p|--path)
                [[ $# -ge 2 ]] || die "--path requires a value"
                EXTRA_SCAN_ROOTS+=("$2")
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

matches_filters() {
    local artifact_name=$1
    local artifact_root=$2
    local filter

    if [[ ${#MATCH_PATTERNS[@]} -eq 0 ]]; then
        return 0
    fi

    for filter in "${MATCH_PATTERNS[@]}"; do
        if [[ "$artifact_name" =~ ${filter} || "$artifact_root" =~ ${filter} ]]; then
            return 0
        fi
    done

    return 1
}

add_artifact_root() {
    local artifact_root=$1
    local artifact_type=$2

    [[ -e "$artifact_root" ]] || return 0
    [[ -n "${SEEN_ROOTS[$artifact_root]:-}" ]] && return 0

    SEEN_ROOTS["$artifact_root"]=1
    ARTIFACT_ROOTS+=("$artifact_root")
    ARTIFACT_TYPES+=("$artifact_type")
}

discover_artifact_roots() {
    local brew_prefix
    local cellar_root
    local caskroom_root
    local formula_root
    local cask_root
    local extra_root

    brew_prefix="$(brew --prefix)"
    cellar_root="$(brew --cellar)"
    caskroom_root="$(brew --caskroom)"

    [[ -d "$cellar_root" ]] || die "Homebrew Cellar not found at $cellar_root"
    [[ -d "$caskroom_root" ]] || info "Homebrew Caskroom not found at $caskroom_root"

    while IFS= read -r formula_root; do
        add_artifact_root "$formula_root" "formula"
    done < <(/usr/bin/find "$cellar_root" -mindepth 2 -maxdepth 2 -type d | /usr/bin/sort)

    if [[ -d "$caskroom_root" ]]; then
        while IFS= read -r cask_root; do
            add_artifact_root "$cask_root" "cask"
        done < <(/usr/bin/find "$caskroom_root" -mindepth 2 -maxdepth 2 -type d | /usr/bin/sort)
    fi

    for extra_root in "${EXTRA_SCAN_ROOTS[@]}"; do
        add_artifact_root "$extra_root" "custom"
    done

    info "Discovered ${#ARTIFACT_ROOTS[@]} artifact roots under $brew_prefix."
}

parse_artifact_identity() {
    local artifact_root=$1
    local artifact_type=$2
    local artifact_name
    local artifact_version

    case "$artifact_type" in
        formula|cask)
            artifact_name="${artifact_root:h:t}"
            artifact_version="${artifact_root:t}"
            ;;
        custom)
            artifact_name="${artifact_root:t}"
            artifact_version="-"
            ;;
        *)
            artifact_name="$artifact_root"
            artifact_version="-"
            ;;
    esac

    printf '%s\t%s\n' "$artifact_name" "$artifact_version"
}

resolve_fix_target() {
    local affected_path=$1
    local resolved_path

    # :P is zsh-specific and resolves symlinks to the canonical on-disk path.
    resolved_path="${affected_path:P}"
    if [[ -n "$resolved_path" ]]; then
        printf '%s\n' "$resolved_path"
    else
        printf '%s\n' "$affected_path"
    fi
}

# Parse the integer flag value from a quarantine attribute string like "01c1;timestamp;app;uuid".
parse_quarantine_flags() {
    local qtn_value=$1
    local flag_hex="${qtn_value%%';'*}"
    if [[ -n "$flag_hex" && "$flag_hex" =~ ^[0-9a-fA-F]+$ ]]; then
        printf '%d\n' "$(( 16#${flag_hex} ))"
    else
        printf '0\n'
    fi
}

# Classify a quarantine finding based on its flag integer.
#   blocking:      QTN_FLAG_DOWNLOAD set, no approval flags — app may be blocked by Gatekeeper
#   approved:      Approval flags set, no HARD flag — app works; soft quarantine removable as owner
#   hard_approved: HARD flag (0x0040) + approval flags — app works; quarantine is a protected
#                  macOS record that cannot be removed via xattr
classify_quarantine() {
    local flags=$1
    local has_hard=$(( flags & 0x40 ))
    local has_approved=$(( (flags & 0x80) | (flags & 0x100) ))

    if [[ $has_hard -ne 0 && $has_approved -ne 0 ]]; then
        printf 'hard_approved'
    elif [[ $has_approved -ne 0 ]]; then
        printf 'approved'
    else
        printf 'blocking'
    fi
}

# Remove com.apple.quarantine from a path, running as the file owner when the
# current process is root. On macOS 26+, quarantine removal via removexattr(2)
# requires the caller to be the file owner; root alone is not sufficient.
xattr_remove_as_owner() {
    local path=$1
    local owner
    owner="$(/usr/bin/stat -f '%Su' "$path" 2>/dev/null)"

    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "$owner" == "$SUDO_USER" ]]; then
        sudo -u "$SUDO_USER" /usr/bin/xattr -d com.apple.quarantine "$path" 2>/dev/null
    else
        /usr/bin/xattr -d com.apple.quarantine "$path" 2>/dev/null
    fi
}

scan_artifact_root() {
    local artifact_root=$1
    local artifact_type=$2
    local identity
    local artifact_name
    local artifact_version
    local raw_file
    local paths_file
    local targets_file
    local hit_count
    local affected_paths
    local fix_targets
    local affected_path
    local resolved_path
    local qtn_value
    local qtn_flags
    local qtn_class

    identity="$(parse_artifact_identity "$artifact_root" "$artifact_type")"
    artifact_name="${identity%%$'\t'*}"
    artifact_version="${identity#*$'\t'}"

    matches_filters "$artifact_name" "$artifact_root" || return 0

    raw_file="$(mktemp /tmp/brew-quarantine-raw.XXXXXX)"
    paths_file="$(mktemp /tmp/brew-quarantine-paths.XXXXXX)"
    targets_file="$(mktemp /tmp/brew-quarantine-targets.XXXXXX)"

    if ! /usr/bin/xattr -r -l "$artifact_root" 2>/dev/null | /usr/bin/grep 'com.apple.quarantine:' > "$raw_file"; then
        rm -f "$raw_file" "$paths_file" "$targets_file"
        return 0
    fi

    /usr/bin/sed 's/: com.apple.quarantine:.*$//' "$raw_file" | /usr/bin/awk '!seen[$0]++' > "$paths_file"
    hit_count="$(/usr/bin/wc -l < "$paths_file" | /usr/bin/tr -d ' ')"

    if [[ "$hit_count" == "0" ]]; then
        rm -f "$raw_file" "$paths_file" "$targets_file"
        return 0
    fi

    # Extract the quarantine value from the first matching raw line to classify this finding.
    qtn_value="$(/usr/bin/awk -F': com.apple.quarantine: ' 'NF>1 {print $NF; exit}' "$raw_file")"
    qtn_flags="$(parse_quarantine_flags "$qtn_value")"
    qtn_class="$(classify_quarantine "$qtn_flags")"

    affected_paths="$(cat "$paths_file")"
    while IFS= read -r affected_path; do
        [[ -n "$affected_path" ]] || continue
        resolved_path="$(resolve_fix_target "$affected_path")"
        printf '%s\n' "$resolved_path" >> "$targets_file"
    done < "$paths_file"
    fix_targets="$(/usr/bin/awk '!seen[$0]++' "$targets_file")"

    FINDING_ROOTS+=("$artifact_root")
    FINDING_TYPES+=("$artifact_type")
    FINDING_NAMES+=("$artifact_name")
    FINDING_VERSIONS+=("$artifact_version")
    FINDING_COUNTS+=("$hit_count")
    FINDING_PATHS+=("$affected_paths")
    FINDING_FIX_TARGETS+=("$fix_targets")
    FINDING_FLAGS+=("$qtn_flags")
    FINDING_CLASSES+=("$qtn_class")

    rm -f "$raw_file" "$paths_file" "$targets_file"
}

scan_for_findings() {
    local index=1
    local artifact_root
    local artifact_type

    for artifact_root in "${ARTIFACT_ROOTS[@]}"; do
        artifact_type="${ARTIFACT_TYPES[$index]}"
        scan_artifact_root "$artifact_root" "$artifact_type"
        index=$((index + 1))
    done
}

print_findings() {
    local finding_total=${#FINDING_ROOTS[@]}
    local index
    local blocking_count=0
    local approved_count=0
    local artifact_label
    local affected_path
    local resolved_path
    local class
    local flags
    local class_label
    local display_index

    # Count findings by class
    for (( index=1; index<=finding_total; index++ )); do
        case "${FINDING_CLASSES[$index]}" in
            blocking)              blocking_count=$(( blocking_count + 1 )) ;;
            approved|hard_approved) approved_count=$(( approved_count + 1 )) ;;
        esac
    done

    if [[ "$blocking_count" -eq 0 && "$approved_count" -eq 0 ]]; then
        success "No Homebrew quarantine findings detected."
        return 0
    fi

    # Show blocking findings (actionable)
    if [[ "$blocking_count" -gt 0 ]]; then
        highlight "Found ${blocking_count} actionable Homebrew quarantine finding(s)."
        display_index=1
        for (( index=1; index<=finding_total; index++ )); do
            [[ "${FINDING_CLASSES[$index]}" == "blocking" ]] || continue
            artifact_label="${FINDING_TYPES[$index]} ${FINDING_NAMES[$index]}"
            [[ "${FINDING_VERSIONS[$index]}" != "-" ]] && artifact_label="${artifact_label} ${FINDING_VERSIONS[$index]}"
            printf '%s\n' ""
            print_colored "$COLOR_CYAN" "[${display_index}] ${artifact_label}"
            printf '  root: %s\n' "${FINDING_ROOTS[$index]}"
            printf '  quarantine hits: %s\n' "${FINDING_COUNTS[$index]}"
            while IFS= read -r affected_path; do
                [[ -n "$affected_path" ]] || continue
                resolved_path="$(resolve_fix_target "$affected_path")"
                if [[ "$resolved_path" == "$affected_path" ]]; then
                    printf '  affected: %s\n' "$affected_path"
                else
                    printf '  affected: %s -> %s\n' "$affected_path" "$resolved_path"
                fi
            done <<< "${FINDING_PATHS[$index]}"
            display_index=$(( display_index + 1 ))
        done
    else
        success "No actionable quarantine findings."
    fi

    # Show approved / hard_approved findings
    if [[ "$approved_count" -gt 0 ]]; then
        if [[ "$INCLUDE_APPROVED" == "true" ]]; then
            printf '\n'
            info "${approved_count} Gatekeeper-approved quarantine record(s) — apps work normally:"
            display_index=1
            for (( index=1; index<=finding_total; index++ )); do
                class="${FINDING_CLASSES[$index]}"
                [[ "$class" == "approved" || "$class" == "hard_approved" ]] || continue
                flags="${FINDING_FLAGS[$index]}"
                artifact_label="${FINDING_TYPES[$index]} ${FINDING_NAMES[$index]}"
                [[ "${FINDING_VERSIONS[$index]}" != "-" ]] && artifact_label="${artifact_label} ${FINDING_VERSIONS[$index]}"
                if [[ "$class" == "hard_approved" ]]; then
                    class_label="HARD — Gatekeeper-protected, cannot remove via xattr"
                else
                    class_label="approved — removable as file owner"
                fi
                printf '%s\n' ""
                print_colored "$COLOR_YELLOW" "[${display_index}] ${artifact_label}"
                printf '  root: %s\n' "${FINDING_ROOTS[$index]}"
                printf '  quarantine flags: 0x%04X (%s)\n' "$flags" "$class_label"
                while IFS= read -r affected_path; do
                    [[ -n "$affected_path" ]] || continue
                    resolved_path="$(resolve_fix_target "$affected_path")"
                    if [[ "$resolved_path" == "$affected_path" ]]; then
                        printf '  affected: %s\n' "$affected_path"
                    else
                        printf '  affected: %s -> %s\n' "$affected_path" "$resolved_path"
                    fi
                done <<< "${FINDING_PATHS[$index]}"
                display_index=$(( display_index + 1 ))
            done
        else
            printf '\n'
            info "${approved_count} app(s) have Gatekeeper-approved quarantine and work normally."
            info "Run with --include-approved to view details."
        fi
    fi
}

# Count findings that will be acted on: blocking always; approved if --include-approved;
# hard_approved never (removal not possible via xattr).
count_actionable() {
    local count=0
    local i
    for (( i=1; i<=${#FINDING_CLASSES[@]}; i++ )); do
        case "${FINDING_CLASSES[$i]}" in
            blocking)
                count=$(( count + 1 ))
                ;;
            approved)
                [[ "$INCLUDE_APPROVED" == "true" ]] && count=$(( count + 1 ))
                ;;
        esac
    done
    printf '%d\n' "$count"
}

confirm_fix() {
    local actionable=$1
    local response

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode enabled. No changes will be made."
        return 1
    fi

    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi

    printf '\nRemove com.apple.quarantine from %s actionable finding(s)? [Y/n]: ' "$actionable"
    IFS= read -r response
    case "$response" in
        ""|y|Y|yes|YES)
            return 0
            ;;
        *)
            info "No changes made."
            return 1
            ;;
    esac
}

fix_findings() {
    local index=1
    local artifact_label
    local success_count=0
    local failure_count=0
    local skipped_hard=0
    local target_failures
    local fix_target
    local class

    while [[ "$index" -le "${#FINDING_ROOTS[@]}" ]]; do
        class="${FINDING_CLASSES[$index]}"

        # Skip approved findings unless --include-approved is set
        if [[ "$class" != "blocking" && "$INCLUDE_APPROVED" == "false" ]]; then
            index=$(( index + 1 ))
            continue
        fi

        artifact_label="${FINDING_TYPES[$index]} ${FINDING_NAMES[$index]}"
        [[ "${FINDING_VERSIONS[$index]}" != "-" ]] && artifact_label="${artifact_label} ${FINDING_VERSIONS[$index]}"

        # Hard approved: Gatekeeper-protected; inform and skip (not a failure)
        if [[ "$class" == "hard_approved" ]]; then
            info "Skipping ${artifact_label}"
            info "  QTN_FLAG_HARD is set: this app is approved and works normally."
            info "  Quarantine cannot be removed via xattr on macOS 26+."
            info "  If a warning appears, open it in Finder → right-click → Open Anyway."
            skipped_hard=$(( skipped_hard + 1 ))
            index=$(( index + 1 ))
            continue
        fi

        highlight "Fixing ${artifact_label}"
        target_failures=0

        while IFS= read -r fix_target; do
            [[ -n "$fix_target" ]] || continue
            # On macOS 26+, quarantine removal requires the file owner's UID,
            # not root. xattr_remove_as_owner switches to SUDO_USER when needed.
            if ! xattr_remove_as_owner "$fix_target"; then
                print_colored "$COLOR_RED" "Failed to remove quarantine from ${fix_target}"
                target_failures=1
            fi
        done <<< "${FINDING_FIX_TARGETS[$index]}"

        if [[ "$target_failures" -eq 0 ]]; then
            success "Removed quarantine from all targets for ${artifact_label}"
            success_count=$(( success_count + 1 ))
        else
            failure_count=$(( failure_count + 1 ))
        fi

        index=$(( index + 1 ))
    done

    printf '\n'
    if [[ "$failure_count" -eq 0 ]]; then
        success "Completed successfully. Fixed ${success_count} finding(s)."
        if [[ "$skipped_hard" -gt 0 ]]; then
            info "${skipped_hard} finding(s) skipped: HARD quarantine (Gatekeeper-protected, apps work normally)."
        fi
    else
        print_colored "$COLOR_RED" "Completed with failures. Fixed ${success_count}, failed ${failure_count} finding(s)."
        if [[ "$EUID" -eq 0 ]]; then
            info "Running as root may cause failures on macOS 26+."
            info "Try rerunning without sudo — quarantine removal requires the file owner's UID."
        fi
        return 1
    fi
}

main() {
    parse_args "$@"

    require_command brew
    require_command xattr
    require_command find
    require_command awk
    require_command sed
    require_command grep
    require_command sort

    # On macOS 26+, quarantine removal via removexattr(2) requires the file owner's
    # UID, not root. xattr_remove_as_owner() switches to SUDO_USER for owner-matched
    # targets, but running without sudo is simpler and avoids the issue entirely.
    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
        info "Running as sudo. Quarantine removal will be attempted as the file owner"
        info "where possible. Consider rerunning without sudo on macOS 26+."
        printf '\n'
    fi

    discover_artifact_roots
    scan_for_findings
    print_findings

    local actionable
    actionable="$(count_actionable)"
    [[ "$actionable" -gt 0 ]] || exit 0

    if confirm_fix "$actionable"; then
        fix_findings
    fi
}

main "$@"
