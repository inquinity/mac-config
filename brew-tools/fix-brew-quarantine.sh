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
    printf '%b%s%b\n' "$color" "$message" "$COLOR_RESET"
}

PROGRAM_NAME="${0:t}"
ASSUME_YES=false
DRY_RUN=false
INCLUDE_APPROVED=false
VERBOSE=false

QTN_FLAG_DOWNLOAD=0x0001
QTN_FLAG_SANDBOX=0x0002
QTN_FLAG_HARD=0x0004
QTN_FLAG_USER_APPROVED=0x0040
QTN_FLAG_NO_TRANSLOCATION=0x0100

typeset -a MATCH_PATTERNS
typeset -a EXTRA_SCAN_ROOTS
typeset -a ARTIFACT_ROOTS
typeset -a ARTIFACT_TYPES
typeset -a FINDING_ROOTS
typeset -a FINDING_TYPES
typeset -a FINDING_NAMES
typeset -a FINDING_VERSIONS
typeset -a FINDING_COUNTS
typeset -a FINDING_ACTIONABLE_COUNTS
typeset -a FINDING_INFORMATIONAL_COUNTS
typeset -a FINDING_DETAILS
typeset -a FINDING_FIX_TARGETS
typeset -a FINDING_CLASSES  # "actionable" or "informational" per finding
typeset -a FINDING_REASONS
typeset -A SEEN_ROOTS

usage() {
    cat <<EOF
Usage: ${PROGRAM_NAME} [options]

Scan Homebrew artifacts for com.apple.quarantine, show affected formulas and
casks, and optionally remove quarantine only from actionable affected paths.

Options:
  -y, --yes              Fix findings without prompting
  -n, --dry-run          Show findings but do not change anything
  -v, --verbose          Show affected paths, quarantine values, and checks
  -a, --include-approved Show user-approved quarantine records skipped by
                         default; these are informational and are not fixed
  -m, --match PATTERN    Only include artifact names or paths matching PATTERN
  -p, --path PATH        Scan an extra artifact root outside Cellar/Caskroom
  -h, --help             Show this help text

Examples:
  ${PROGRAM_NAME}
  ${PROGRAM_NAME} --yes
  ${PROGRAM_NAME} --dry-run
  ${PROGRAM_NAME} --verbose
  ${PROGRAM_NAME} --verbose --yes
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
            -v|--verbose)
                VERBOSE=true
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

has_user_approved() {
    local flags=$1
    (( flags & QTN_FLAG_USER_APPROVED ))
}

describe_quarantine_flags() {
    local flags=$1
    local known_flags=0
    local unknown_flags
    local -a labels

    if (( flags & QTN_FLAG_DOWNLOAD )); then
        labels+=("downloaded")
        known_flags=$(( known_flags | QTN_FLAG_DOWNLOAD ))
    fi
    if (( flags & QTN_FLAG_SANDBOX )); then
        labels+=("sandboxed")
        known_flags=$(( known_flags | QTN_FLAG_SANDBOX ))
    fi
    if (( flags & QTN_FLAG_HARD )); then
        labels+=("hard")
        known_flags=$(( known_flags | QTN_FLAG_HARD ))
    fi
    if (( flags & QTN_FLAG_USER_APPROVED )); then
        labels+=("user-approved")
        known_flags=$(( known_flags | QTN_FLAG_USER_APPROVED ))
    fi
    if (( flags & QTN_FLAG_NO_TRANSLOCATION )); then
        labels+=("no-translocation")
        known_flags=$(( known_flags | QTN_FLAG_NO_TRANSLOCATION ))
    fi

    unknown_flags=$(( flags & ~known_flags ))
    if (( unknown_flags != 0 )); then
        labels+=("other $(printf '0x%04X' "$unknown_flags")")
    fi

    if (( ${#labels[@]} == 0 )); then
        printf 'none\n'
    else
        printf '%s\n' "${(j:, :)labels}"
    fi
}

is_gatekeeper_candidate() {
    local path=$1

    [[ -d "$path" && "$path" == *.app ]] && return 0
    [[ -f "$path" && -x "$path" ]] && return 0
    [[ -e "$path" && "$path" == *.pkg ]] && return 0

    return 1
}

assess_code_signing() {
    local path=$1
    local output
    local first_line

    if [[ ! -e "$path" ]]; then
        printf 'missing\tpath no longer exists\n'
        return 0
    fi

    if ! is_gatekeeper_candidate "$path"; then
        printf 'not_checked\tnot an executable, app bundle, or package\n'
        return 0
    fi

    if [[ ! -x /usr/bin/codesign ]]; then
        printf 'not_checked\tcodesign is not available\n'
        return 0
    fi

    if output="$(/usr/bin/codesign --verify --deep --strict "$path" 2>&1)"; then
        printf 'valid\tcodesign verification passed\n'
        return 0
    fi

    first_line="${output%%$'\n'*}"
    first_line="${first_line//$'\t'/ }"
    [[ -n "$first_line" ]] || first_line="codesign verification failed"

    case "$first_line" in
        *"invalid signature"*|*"code or signature have been modified"*)
            printf 'invalid_signature\t%s\n' "$first_line"
            ;;
        *"code object is not signed at all"*|*"is not signed at all"*)
            printf 'unsigned\t%s\n' "$first_line"
            ;;
        *)
            printf 'not_verifiable\t%s\n' "$first_line"
            ;;
    esac
}

classify_quarantine_path() {
    local flags=$1
    local codesign_status=$2

    if [[ "$codesign_status" == "invalid_signature" ]]; then
        printf 'actionable\n'
        return 0
    fi

    if ! has_user_approved "$flags"; then
        printf 'actionable\n'
        return 0
    fi

    printf 'informational\n'
}

reason_for_quarantine_path() {
    local flags=$1
    local codesign_status=$2

    if [[ "$codesign_status" == "invalid_signature" ]]; then
        printf 'invalid code signature\n'
    elif ! has_user_approved "$flags"; then
        if (( flags & QTN_FLAG_HARD )); then
            printf 'hard quarantine without user approval\n'
        else
            printf 'quarantine without user approval\n'
        fi
    else
        printf 'user-approved quarantine record\n'
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
    local pairs_file
    local details_file
    local targets_file
    local reasons_file
    local hit_count
    local fix_targets
    local details
    local reasons
    local affected_path
    local resolved_path
    local qtn_value
    local qtn_flags
    local flag_description
    local codesign_result
    local codesign_status
    local codesign_detail
    local path_class
    local reason
    local artifact_class
    local actionable_count=0
    local informational_count=0

    identity="$(parse_artifact_identity "$artifact_root" "$artifact_type")"
    artifact_name="${identity%%$'\t'*}"
    artifact_version="${identity#*$'\t'}"

    matches_filters "$artifact_name" "$artifact_root" || return 0

    pairs_file="$(mktemp /tmp/brew-quarantine-pairs.XXXXXX)"
    details_file="$(mktemp /tmp/brew-quarantine-details.XXXXXX)"
    targets_file="$(mktemp /tmp/brew-quarantine-targets.XXXXXX)"
    reasons_file="$(mktemp /tmp/brew-quarantine-reasons.XXXXXX)"

    /usr/bin/xattr -r -l "$artifact_root" 2>/dev/null \
        | /usr/bin/awk -F': com.apple.quarantine: ' 'NF > 1 && !seen[$1]++ { print $1 "\t" $NF }' \
        > "$pairs_file" || true

    hit_count="$(/usr/bin/wc -l < "$pairs_file" | /usr/bin/tr -d ' ')"

    if [[ "$hit_count" == "0" ]]; then
        rm -f "$pairs_file" "$details_file" "$targets_file" "$reasons_file"
        return 0
    fi

    while IFS=$'\t' read -r affected_path qtn_value; do
        [[ -n "$affected_path" ]] || continue
        [[ -n "$qtn_value" ]] || qtn_value="-"

        resolved_path="$(resolve_fix_target "$affected_path")"
        qtn_flags="$(parse_quarantine_flags "$qtn_value")"
        flag_description="$(describe_quarantine_flags "$qtn_flags")"
        codesign_result="$(assess_code_signing "$resolved_path")"
        codesign_status="${codesign_result%%$'\t'*}"
        codesign_detail="${codesign_result#*$'\t'}"
        [[ "$codesign_detail" != "$codesign_result" ]] || codesign_detail="-"
        path_class="$(classify_quarantine_path "$qtn_flags" "$codesign_status")"
        reason="$(reason_for_quarantine_path "$qtn_flags" "$codesign_status")"

        if [[ "$path_class" == "actionable" ]]; then
            actionable_count=$(( actionable_count + 1 ))
            printf '%s\n' "$resolved_path" >> "$targets_file"
        else
            informational_count=$(( informational_count + 1 ))
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$path_class" \
            "$affected_path" \
            "$resolved_path" \
            "$qtn_value" \
            "$qtn_flags" \
            "$flag_description" \
            "$codesign_status" \
            "$codesign_detail" \
            "$reason" >> "$details_file"
        printf '%s\n' "$reason" >> "$reasons_file"
    done < "$pairs_file"

    fix_targets="$(/usr/bin/awk '!seen[$0]++' "$targets_file")"
    details="$(< "$details_file")"
    reasons="$(/usr/bin/awk 'BEGIN { separator="" } NF > 0 && !seen[$0]++ { printf "%s%s", separator, $0; separator=", " } END { if (separator != "") printf "\n" }' "$reasons_file")"

    if [[ "$actionable_count" -gt 0 ]]; then
        artifact_class="actionable"
    else
        artifact_class="informational"
    fi

    FINDING_ROOTS+=("$artifact_root")
    FINDING_TYPES+=("$artifact_type")
    FINDING_NAMES+=("$artifact_name")
    FINDING_VERSIONS+=("$artifact_version")
    FINDING_COUNTS+=("$hit_count")
    FINDING_ACTIONABLE_COUNTS+=("$actionable_count")
    FINDING_INFORMATIONAL_COUNTS+=("$informational_count")
    FINDING_DETAILS+=("$details")
    FINDING_FIX_TARGETS+=("$fix_targets")
    FINDING_CLASSES+=("$artifact_class")
    FINDING_REASONS+=("$reasons")

    rm -f "$pairs_file" "$details_file" "$targets_file" "$reasons_file"
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

artifact_label_at() {
    local index=$1
    local artifact_label

    artifact_label="${FINDING_TYPES[$index]} ${FINDING_NAMES[$index]}"
    [[ "${FINDING_VERSIONS[$index]}" != "-" ]] && artifact_label="${artifact_label} ${FINDING_VERSIONS[$index]}"
    printf '%s\n' "$artifact_label"
}

print_detail_lines() {
    local details=$1
    local detail_filter=$2
    local path_class
    local affected_path
    local resolved_path
    local qtn_value
    local qtn_flags
    local flag_description
    local codesign_status
    local codesign_detail
    local reason

    while IFS=$'\t' read -r path_class affected_path resolved_path qtn_value qtn_flags flag_description codesign_status codesign_detail reason; do
        [[ -n "$affected_path" ]] || continue
        [[ "$detail_filter" == "all" || "$path_class" == "$detail_filter" ]] || continue

        if [[ "$path_class" == "actionable" ]]; then
            print_colored "$COLOR_CYAN" "  - actionable: ${affected_path}"
        else
            print_colored "$COLOR_YELLOW" "  - informational: ${affected_path}"
        fi
        [[ "$resolved_path" == "$affected_path" ]] || printf '    resolved: %s\n' "$resolved_path"
        printf '    reason: %s\n' "$reason"
        printf '    quarantine: %s\n' "$qtn_value"
        printf '    flags: 0x%04X (%s)\n' "$qtn_flags" "$flag_description"
        printf '    codesign: %s - %s\n' "$codesign_status" "$codesign_detail"
    done <<< "$details"
}

print_findings() {
    local finding_total=${#FINDING_ROOTS[@]}
    local index
    local actionable_artifact_count=0
    local informational_path_count=0
    local artifact_label
    local display_index
    local detail_filter

    for (( index=1; index<=finding_total; index++ )); do
        if [[ "${FINDING_CLASSES[$index]}" == "actionable" ]]; then
            actionable_artifact_count=$(( actionable_artifact_count + 1 ))
        fi
        informational_path_count=$(( informational_path_count + FINDING_INFORMATIONAL_COUNTS[$index] ))
    done

    if [[ "$finding_total" -eq 0 ]]; then
        success "No Homebrew quarantine findings detected."
        return 0
    fi

    if [[ "$actionable_artifact_count" -gt 0 ]]; then
        highlight "Found ${actionable_artifact_count} actionable Homebrew quarantine finding(s)."
        display_index=1
        for (( index=1; index<=finding_total; index++ )); do
            [[ "${FINDING_CLASSES[$index]}" == "actionable" ]] || continue
            artifact_label="$(artifact_label_at "$index")"

            printf '%s\n' ""
            print_colored "$COLOR_CYAN" "[${display_index}] ${artifact_label} (${FINDING_ACTIONABLE_COUNTS[$index]} affected path(s))"
            if [[ "$INCLUDE_APPROVED" == "true" && "${FINDING_INFORMATIONAL_COUNTS[$index]}" -gt 0 ]]; then
                printf '  informational paths also present: %s\n' "${FINDING_INFORMATIONAL_COUNTS[$index]}"
            fi

            if [[ "$VERBOSE" == "true" ]]; then
                printf '  root: %s\n' "${FINDING_ROOTS[$index]}"
                [[ -z "${FINDING_REASONS[$index]}" ]] || printf '  reasons: %s\n' "${FINDING_REASONS[$index]}"
                if [[ "$INCLUDE_APPROVED" == "true" ]]; then
                    detail_filter="all"
                else
                    detail_filter="actionable"
                fi
                print_detail_lines "${FINDING_DETAILS[$index]}" "$detail_filter"
            fi

            display_index=$(( display_index + 1 ))
        done
    else
        success "No actionable Homebrew quarantine findings."
    fi

    if [[ "$informational_path_count" -gt 0 ]]; then
        if [[ "$INCLUDE_APPROVED" == "true" ]]; then
            printf '\n'
            info "Informational user-approved quarantine record(s), not fixed:"
            display_index=1
            for (( index=1; index<=finding_total; index++ )); do
                [[ "${FINDING_CLASSES[$index]}" == "informational" ]] || continue
                artifact_label="$(artifact_label_at "$index")"
                printf '%s\n' ""
                print_colored "$COLOR_YELLOW" "[${display_index}] ${artifact_label} (${FINDING_INFORMATIONAL_COUNTS[$index]} informational path(s))"
                if [[ "$VERBOSE" == "true" ]]; then
                    printf '  root: %s\n' "${FINDING_ROOTS[$index]}"
                    [[ -z "${FINDING_REASONS[$index]}" ]] || printf '  reasons: %s\n' "${FINDING_REASONS[$index]}"
                    print_detail_lines "${FINDING_DETAILS[$index]}" "informational"
                fi
                display_index=$(( display_index + 1 ))
            done
        else
            printf '\n'
            info "${informational_path_count} user-approved quarantine path(s) skipped as informational."
            info "Run with --include-approved --verbose to view them."
        fi
    fi
}

# Count artifacts that will be acted on. Informational user-approved records are
# shown only when requested and are never removed by --yes.
count_actionable() {
    local count=0
    local index

    for (( index=1; index<=${#FINDING_CLASSES[@]}; index++ )); do
        [[ "${FINDING_CLASSES[$index]}" == "actionable" ]] && count=$(( count + 1 ))
    done

    printf '%d\n' "$count"
}

confirm_fix() {
    local actionable=$1
    local response

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode enabled; exiting..."
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
    local target_failures
    local fix_target

    while [[ "$index" -le "${#FINDING_ROOTS[@]}" ]]; do
        if [[ "${FINDING_CLASSES[$index]}" != "actionable" ]]; then
            index=$(( index + 1 ))
            continue
        fi

        artifact_label="$(artifact_label_at "$index")"
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
    require_command mktemp
    require_command sort
    require_command tr
    require_command wc

    # On macOS 26+, quarantine removal via removexattr(2) requires the file owner's
    # UID, not root. xattr_remove_as_owner() switches to SUDO_USER for owner-matched
    # targets, but running without sudo is simpler and avoids the issue entirely.
    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
        info "Running as sudo. Quarantine removal will be attempted as the file owner"
        info "where possible. Consider rerunning without sudo on macOS 26+."
        printf '\n'
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode enabled. No changes will be made."
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
