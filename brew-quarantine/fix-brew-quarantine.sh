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
typeset -A SEEN_ROOTS

usage() {
    cat <<EOF
Usage: ${PROGRAM_NAME} [options]

Scan Homebrew artifacts for com.apple.quarantine, show what is affected,
and optionally remove the attribute from only the affected artifact roots.

Options:
  -y, --yes              Fix findings without prompting
  -n, --dry-run          Show findings but do not change anything
  -m, --match PATTERN    Only include artifact names or paths matching PATTERN
  -p, --path PATH        Scan an extra artifact root outside Cellar/Caskroom
  -h, --help             Show this help text

Examples:
  ${PROGRAM_NAME}
  ${PROGRAM_NAME} --dry-run
  ${PROGRAM_NAME} --match 'codex|codeql|openjdk'
  sudo ${PROGRAM_NAME} --yes
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
    local index=1
    local artifact_label
    local affected_path
    local resolved_path

    if [[ "$finding_total" -eq 0 ]]; then
        success "No Homebrew quarantine findings detected."
        return 0
    fi

    highlight "Found ${finding_total} Homebrew artifacts with com.apple.quarantine."

    while [[ "$index" -le "$finding_total" ]]; do
        artifact_label="${FINDING_TYPES[$index]} ${FINDING_NAMES[$index]}"
        if [[ "${FINDING_VERSIONS[$index]}" != "-" ]]; then
            artifact_label="${artifact_label} ${FINDING_VERSIONS[$index]}"
        fi

        printf '%s\n' ""
        print_colored "$COLOR_CYAN" "[$index] ${artifact_label}"
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

        index=$((index + 1))
    done
}

confirm_fix() {
    local response

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode enabled. No changes will be made."
        return 1
    fi

    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi

    printf '\nRemove com.apple.quarantine from all %s listed findings and their resolved targets? [Y/n]: ' "${#FINDING_ROOTS[@]}"
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
    local target_failures
    local fix_target

    while [[ "$index" -le "${#FINDING_ROOTS[@]}" ]]; do
        artifact_label="${FINDING_TYPES[$index]} ${FINDING_NAMES[$index]}"
        if [[ "${FINDING_VERSIONS[$index]}" != "-" ]]; then
            artifact_label="${artifact_label} ${FINDING_VERSIONS[$index]}"
        fi

        highlight "Fixing ${artifact_label}"
        target_failures=0
        while IFS= read -r fix_target; do
            [[ -n "$fix_target" ]] || continue
            if ! /usr/bin/xattr -r -d com.apple.quarantine "$fix_target" 2>/dev/null; then
                print_colored "$COLOR_RED" "Failed to remove quarantine from ${fix_target}"
                target_failures=1
            fi
        done <<< "${FINDING_FIX_TARGETS[$index]}"

        if [[ "$target_failures" -eq 0 ]]; then
            success "Removed quarantine from all targets for ${artifact_label}"
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi

        index=$((index + 1))
    done

    printf '\n'
    if [[ "$failure_count" -eq 0 ]]; then
        success "Completed successfully. Fixed ${success_count} findings."
    else
        print_colored "$COLOR_RED" "Completed with failures. Fixed ${success_count}, failed ${failure_count} findings."
        if [[ "$EUID" -ne 0 ]]; then
            info "If failures were permission-related, rerun with sudo."
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

    discover_artifact_roots
    scan_for_findings
    print_findings

    [[ ${#FINDING_ROOTS[@]} -gt 0 ]] || exit 0

    if confirm_fix; then
        fix_findings
    fi
}

main "$@"
