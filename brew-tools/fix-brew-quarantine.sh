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
WRITE_LOG=false
LOG_FILE="${HOME}/Library/Logs/fix-brew-quarantine.log"

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
typeset -a FINDING_KINDS     # distinct target kinds seen under the finding
typeset -a FINDING_OUTCOMES  # filled in by fix_findings; used by the log
typeset -A SEEN_ROOTS

# Scratch directory for the per-root temp files; created in main() and removed by
# cleanup() so an interrupted scan does not leave files behind in /tmp.
typeset TEMP_DIR=""

# Only this many failing paths are printed individually before the output is
# summarised; a protected cask can fail on thousands of paths at once.
typeset -i FAILURE_SAMPLE_LIMIT=5

# The per-path helpers below assign to these globals rather than printing into a
# $( ) command substitution. A cask like codeql stages ~5.7k quarantined paths,
# and at seven subshells per path the forks dominated the entire scan.
typeset -i QTN_FLAGS=0
typeset QTN_FLAG_DESCRIPTION=""
typeset CODESIGN_STATUS=""
typeset CODESIGN_DETAIL=""
typeset GATEKEEPER_STATUS=""
typeset GATEKEEPER_DETAIL=""
typeset PATH_CLASS=""
typeset PATH_REASON=""
typeset TARGET_KIND=""

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
  -l, --log [FILE]       Append one tab-separated line per finding to FILE
                         (default: ~/Library/Logs/fix-brew-quarantine.log) to
                         build up a record of which artifacts recur and why
  -h, --help             Show this help text

Examples:
  ${PROGRAM_NAME}
  ${PROGRAM_NAME} --yes
  ${PROGRAM_NAME} --dry-run
  ${PROGRAM_NAME} --verbose
  ${PROGRAM_NAME} --verbose --yes
  ${PROGRAM_NAME} --match 'codex|codeql|openjdk'
  ${PROGRAM_NAME} --yes --log
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

cleanup() {
    # /bin/rm by absolute path, and never fatal: when a signal trap fires inside
    # a nested function while a command substitution is in flight, zsh cannot
    # resolve bare command names from $PATH, so a bare `rm` here dies with status
    # 127 and leaves the scratch directory behind — exactly the Ctrl-C case the
    # trap exists to handle.
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && /bin/rm -rf "$TEMP_DIR"
    TEMP_DIR=""
    return 0
}

# Progress goes to stderr with a carriage return so it stays on one line and
# never pollutes piped or redirected output. Without it a large cask looks hung
# for minutes between the scan starting and the first finding being printed.
progress() {
    local message=$1

    [[ -t 2 ]] || return 0
    printf '\r\e[2K%s' "$message" >&2
}

progress_done() {
    [[ -t 2 ]] || return 0
    printf '\r\e[2K' >&2
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
            -l|--log)
                WRITE_LOG=true
                # The path is optional, so only consume the next argument when it
                # is a value rather than the next option.
                if [[ $# -ge 2 && "$2" != -* ]]; then
                    LOG_FILE="$2"
                    shift
                fi
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
            # Caskroom/<cask>/.metadata sits at the same depth as a version
            # directory but holds Homebrew's install receipts, not the artifact.
            [[ "${cask_root:t}" == ".metadata" ]] && continue
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

# Parse the integer flag value from a quarantine attribute string like
# "01c1;timestamp;app;uuid" into QTN_FLAGS.
parse_quarantine_flags() {
    local qtn_value=$1
    local flag_hex="${qtn_value%%';'*}"

    if [[ -n "$flag_hex" && "$flag_hex" =~ ^[0-9a-fA-F]+$ ]]; then
        QTN_FLAGS=$(( 16#${flag_hex} ))
    else
        QTN_FLAGS=0
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
        QTN_FLAG_DESCRIPTION="none"
    else
        QTN_FLAG_DESCRIPTION="${(j:, :)labels}"
    fi
}

# Classify what kind of thing a path is, which decides how it can be assessed.
# A standalone Mach-O executable cannot carry a stapled notarization ticket at
# all, so spctl has nothing to work with and never returns a useful verdict for
# one. Bundles and packages *can* carry a ticket, though on a Homebrew-managed
# machine they usually do not: Homebrew mounts the delivered .dmg, copies the
# payload out and discards the container the ticket was stapled to. Their spctl
# verdict is therefore real but generally comes from an online or cached notary
# check rather than a local ticket.
#   app    bundle directory        -> assess with spctl -t execute
#   pkg    installer package       -> assess with spctl -t install
#   binary standalone executable   -> no useful spctl verdict; codesign only
#   data   anything else           -> not subject to Gatekeeper assessment
classify_assessment_target() {
    local path=$1

    if [[ -d "$path" && "$path" == *.app ]]; then
        TARGET_KIND="app"
    elif [[ -e "$path" && ( "$path" == *.pkg || "$path" == *.mpkg ) ]]; then
        TARGET_KIND="pkg"
    elif [[ -f "$path" && -x "$path" ]]; then
        TARGET_KIND="binary"
    else
        TARGET_KIND="data"
    fi
}

is_gatekeeper_candidate() {
    [[ "$TARGET_KIND" != "data" ]]
}

assess_code_signing() {
    local path=$1
    local output
    local first_line

    if [[ ! -e "$path" ]]; then
        CODESIGN_STATUS="missing"
        CODESIGN_DETAIL="path no longer exists"
        return 0
    fi

    if ! is_gatekeeper_candidate "$path"; then
        CODESIGN_STATUS="not_checked"
        CODESIGN_DETAIL="not an executable, app bundle, or package"
        return 0
    fi

    # A flat installer package carries a CMS package signature, not a Mach-O code
    # signature, so codesign reports it as "not signed at all" no matter how it
    # was signed. Reporting that verbatim reads as a finding when it is not one;
    # spctl -t install is the check that actually applies.
    if [[ "$TARGET_KIND" == "pkg" ]]; then
        CODESIGN_STATUS="not_checked"
        CODESIGN_DETAIL="package signature is validated by spctl -t install, not codesign"
        return 0
    fi

    if [[ ! -x /usr/bin/codesign ]]; then
        CODESIGN_STATUS="not_checked"
        CODESIGN_DETAIL="codesign is not available"
        return 0
    fi

    # --deep recurses into nested code, which matters for an app bundle or a
    # package and does nothing for a standalone Mach-O.
    local -a verify_flags=(--verify --strict)
    [[ "$TARGET_KIND" == "binary" ]] || verify_flags+=(--deep)

    if output="$(/usr/bin/codesign "${verify_flags[@]}" "$path" 2>&1)"; then
        CODESIGN_STATUS="valid"
        CODESIGN_DETAIL="codesign verification passed"
        return 0
    fi

    first_line="${output%%$'\n'*}"
    first_line="${first_line//$'\t'/ }"
    [[ -n "$first_line" ]] || first_line="codesign verification failed"
    CODESIGN_DETAIL="$first_line"

    case "$first_line" in
        *"invalid signature"*|*"code or signature have been modified"*)
            CODESIGN_STATUS="invalid_signature"
            ;;
        *"code object is not signed at all"*|*"is not signed at all"*)
            CODESIGN_STATUS="unsigned"
            ;;
        *)
            CODESIGN_STATUS="not_verifiable"
            ;;
    esac
}

# Ask Gatekeeper for its actual execute-time verdict on a path. This is the
# authoritative check for whether macOS will block the item (e.g. the
# "Not Opened" dialog): codesign validity alone only proves the signature is
# intact, not that the item is notarized/approved to run.
assess_gatekeeper() {
    local path=$1
    local output
    local source_line
    local assessment_type

    if [[ ! -e "$path" ]]; then
        GATEKEEPER_STATUS="missing"
        GATEKEEPER_DETAIL="path no longer exists"
        return 0
    fi

    if ! is_gatekeeper_candidate "$path"; then
        GATEKEEPER_STATUS="not_checked"
        GATEKEEPER_DETAIL="not an executable, app bundle, or package"
        return 0
    fi

    # A standalone executable cannot have a notarization ticket stapled to it, so
    # spctl has nothing local to validate and reports "rejected" even for a
    # properly signed and notarized tool. Asking is both useless and the single
    # most expensive check in the script: 64s across the 674 executables of the
    # codeql cask, versus 20s for codesign over the same set. Skip it and let the
    # signature state supply the reason instead.
    if [[ "$TARGET_KIND" == "binary" ]]; then
        GATEKEEPER_STATUS="not_assessable"
        GATEKEEPER_DETAIL="standalone executable; cannot carry a notarization ticket, so spctl cannot assess it"
        return 0
    fi

    if [[ ! -x /usr/sbin/spctl ]]; then
        GATEKEEPER_STATUS="not_checked"
        GATEKEEPER_DETAIL="spctl is not available"
        return 0
    fi

    # The assessment type has to match the artifact: an installer package probed
    # with -t execute reports "no usable signature" even when it is notarized.
    # Observed on the git-credential-manager cask, where -t execute rejects the
    # same .pkg that -t install accepts as Notarized Developer ID.
    if [[ "$TARGET_KIND" == "pkg" ]]; then
        assessment_type="install"
    else
        assessment_type="execute"
    fi

    if output="$(/usr/sbin/spctl -a -vv -t "$assessment_type" "$path" 2>&1)"; then
        source_line="$(printf '%s\n' "$output" | /usr/bin/grep '^source=' || true)"
        GATEKEEPER_STATUS="accepted"
        GATEKEEPER_DETAIL="${source_line:-spctl accepted} (-t ${assessment_type})"
        return 0
    fi

    source_line="$(printf '%s\n' "$output" | /usr/bin/grep '^source=' || true)"
    GATEKEEPER_STATUS="rejected"
    GATEKEEPER_DETAIL="${source_line:-spctl rejected} (-t ${assessment_type})"
}

# Assess a path, cheapest decision first. The kind classification is what keeps
# this affordable: spctl is only asked about bundles and packages, of which a
# cask has one or two, instead of every executable in the payload.
assess_path_trust() {
    local path=$1

    classify_assessment_target "$path"
    assess_code_signing "$path"
    assess_gatekeeper "$path"
}

# Reads QTN_FLAGS, CODESIGN_STATUS, GATEKEEPER_STATUS and TARGET_KIND; sets
# PATH_CLASS.
classify_quarantine_path() {
    if [[ "$CODESIGN_STATUS" == "invalid_signature" ]]; then
        PATH_CLASS="actionable"
        return 0
    fi

    if has_user_approved "$QTN_FLAGS"; then
        PATH_CLASS="informational"
        return 0
    fi

    # Only app and pkg targets can be cleared this way, because spctl can only
    # give a meaningful verdict for those; see assess_gatekeeper(). Note that
    # acceptance here does not imply a locally stapled ticket — on a
    # Homebrew-managed machine it generally is not one, since Homebrew extracts
    # the payload and discards the stapled container. It means macOS will allow
    # the item to run, which is what "no action needed" is about.
    if [[ "$GATEKEEPER_STATUS" == "accepted" ]]; then
        PATH_CLASS="informational"
        return 0
    fi

    PATH_CLASS="actionable"
}

# Reads the same globals as classify_quarantine_path; sets PATH_REASON.
# The unstapleable cases are split by signature state rather than reported as one
# generic rejection: a standalone binary can be properly signed and notarized, be
# signed but unnotarized, or be unsigned outright, and only the last is a
# concern beyond the quarantine flag itself.
reason_for_quarantine_path() {
    if [[ "$CODESIGN_STATUS" == "invalid_signature" ]]; then
        PATH_REASON="invalid code signature"
    elif has_user_approved "$QTN_FLAGS"; then
        PATH_REASON="user-approved quarantine record"
    elif [[ "$GATEKEEPER_STATUS" == "accepted" ]]; then
        PATH_REASON="Gatekeeper accepts this ${TARGET_KIND} (notarized; no user action needed)"
    elif [[ "$GATEKEEPER_STATUS" == "not_assessable" ]]; then
        case "$CODESIGN_STATUS" in
            valid)
                PATH_REASON="signed standalone executable, cannot be Gatekeeper-assessed; quarantine removal required"
                ;;
            unsigned)
                PATH_REASON="unsigned standalone executable; quarantine removal required"
                ;;
            *)
                PATH_REASON="standalone executable, signature ${CODESIGN_STATUS}; quarantine removal required"
                ;;
        esac
    elif [[ "$GATEKEEPER_STATUS" == "rejected" ]]; then
        PATH_REASON="Gatekeeper rejects this ${TARGET_KIND} (${GATEKEEPER_DETAIL}); quarantine removal required"
    elif (( QTN_FLAGS & QTN_FLAG_HARD )); then
        PATH_REASON="hard quarantine without user approval"
    else
        PATH_REASON="quarantine without user approval"
    fi
}

# Remove com.apple.quarantine from a path. When running as root, switches to
# the file owner's UID first (required on macOS 26+ where root alone is not
# sufficient). When running as a normal user, falls back to sudo if the direct
# removal fails — this handles paths installed to /Applications with admin
# ownership (e.g. Homebrew casks that resolve symlinks to system directories).
xattr_remove_as_owner() {
    local path=$1
    local owner
    owner="$(/usr/bin/stat -f '%Su' "$path" 2>/dev/null)"

    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "$owner" == "$SUDO_USER" ]]; then
        sudo -u "$SUDO_USER" /usr/bin/xattr -d com.apple.quarantine "$path" 2>/dev/null
    elif /usr/bin/xattr -d com.apple.quarantine "$path" 2>/dev/null; then
        return 0
    else
        sudo /usr/bin/xattr -d com.apple.quarantine "$path" 2>/dev/null
    fi
}

scan_artifact_root() {
    local artifact_root=$1
    local artifact_type=$2
    local identity
    local artifact_name
    local artifact_version
    local pairs_file="$TEMP_DIR/pairs"
    local details_file="$TEMP_DIR/details"
    local targets_file="$TEMP_DIR/targets"
    local details_fd
    local targets_fd
    local hit_count
    local fix_targets
    local details
    local reasons
    local kinds
    local affected_path
    local resolved_path
    local qtn_value
    local artifact_class
    local path_index=0
    local actionable_count=0
    local informational_count=0

    identity="$(parse_artifact_identity "$artifact_root" "$artifact_type")"
    artifact_name="${identity%%$'\t'*}"
    artifact_version="${identity#*$'\t'}"

    matches_filters "$artifact_name" "$artifact_root" || return 0

    : > "$pairs_file"

    # xattr -l dumps binary attribute values (resource forks, signatures); LC_ALL=C
    # keeps awk from failing multibyte conversion on them.
    /usr/bin/xattr -r -l "$artifact_root" 2>/dev/null \
        | LC_ALL=C /usr/bin/awk -F': com.apple.quarantine: ' 'NF > 1 && !seen[$1]++ { print $1 "\t" $NF }' \
        > "$pairs_file" || true

    hit_count=$(/usr/bin/wc -l < "$pairs_file")
    hit_count=$(( hit_count ))

    if (( hit_count == 0 )); then
        return 0
    fi

    # Both output files are held open for the whole loop. Reopening them per path
    # with >> costs ~19ms each, which dwarfed every other per-path cost: on the
    # ~5.7k paths of the codeql cask that alone was minutes of wall time.
    # {var}> fd allocation needs zsh or bash 4.1+.
    exec {details_fd}>"$details_file"
    exec {targets_fd}>"$targets_file"

    # Every helper called here assigns to a global instead of printing into a
    # subshell; see the QTN_FLAGS block near the top of the script.
    while IFS=$'\t' read -r affected_path qtn_value; do
        [[ -n "$affected_path" ]] || continue
        [[ -n "$qtn_value" ]] || qtn_value="-"

        path_index=$(( path_index + 1 ))
        if (( path_index % 250 == 0 )); then
            progress "Checking ${artifact_name}: ${path_index}/${hit_count} quarantined path(s)"
        fi

        # :P is zsh-specific and resolves symlinks to the canonical on-disk path.
        resolved_path="${affected_path:P}"
        [[ -n "$resolved_path" ]] || resolved_path="$affected_path"

        parse_quarantine_flags "$qtn_value"
        describe_quarantine_flags "$QTN_FLAGS"
        assess_path_trust "$resolved_path"
        classify_quarantine_path
        reason_for_quarantine_path

        if [[ "$PATH_CLASS" == "actionable" ]]; then
            actionable_count=$(( actionable_count + 1 ))
            printf '%s\n' "$resolved_path" >&$targets_fd
        else
            informational_count=$(( informational_count + 1 ))
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$PATH_CLASS" \
            "$affected_path" \
            "$resolved_path" \
            "$qtn_value" \
            "$QTN_FLAGS" \
            "$QTN_FLAG_DESCRIPTION" \
            "$CODESIGN_STATUS" \
            "$CODESIGN_DETAIL" \
            "$GATEKEEPER_STATUS" \
            "$GATEKEEPER_DETAIL" \
            "$PATH_REASON" \
            "$TARGET_KIND" >&$details_fd
    done < "$pairs_file"

    exec {details_fd}>&-
    exec {targets_fd}>&-

    fix_targets="$(/usr/bin/awk '!seen[$0]++' "$targets_file")"
    details="$(< "$details_file")"
    # Field 11 of each detail line is the reason, so the distinct reasons come
    # straight out of the details rather than needing a second output file.
    reasons="$(LC_ALL=C /usr/bin/awk -F'\t' 'BEGIN { separator="" } NF >= 11 && !seen[$11]++ { printf "%s%s", separator, $11; separator=", " } END { if (separator != "") printf "\n" }' "$details_file")"
    # Field 12 is the target kind; the distinct set describes the payload shape.
    kinds="$(LC_ALL=C /usr/bin/awk -F'\t' 'BEGIN { separator="" } NF >= 12 && !seen[$12]++ { printf "%s%s", separator, $12; separator="," } END { if (separator != "") printf "\n" }' "$details_file")"

    if (( actionable_count > 0 )); then
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
    FINDING_KINDS+=("$kinds")
    FINDING_OUTCOMES+=("not-attempted")
}

scan_for_findings() {
    local index=1
    local root_total=${#ARTIFACT_ROOTS[@]}
    local artifact_root
    local artifact_type

    for artifact_root in "${ARTIFACT_ROOTS[@]}"; do
        artifact_type="${ARTIFACT_TYPES[$index]}"
        progress "Scanning ${index}/${root_total}: ${artifact_root:t}"
        scan_artifact_root "$artifact_root" "$artifact_type"
        index=$((index + 1))
    done

    progress_done
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
    local gatekeeper_status
    local gatekeeper_detail
    local reason
    local target_kind

    while IFS=$'\t' read -r path_class affected_path resolved_path qtn_value qtn_flags flag_description codesign_status codesign_detail gatekeeper_status gatekeeper_detail reason target_kind; do
        [[ -n "$affected_path" ]] || continue
        [[ "$detail_filter" == "all" || "$path_class" == "$detail_filter" ]] || continue

        if [[ "$path_class" == "actionable" ]]; then
            print_colored "$COLOR_CYAN" "  - actionable: ${affected_path}"
        else
            print_colored "$COLOR_YELLOW" "  - informational: ${affected_path}"
        fi
        [[ "$resolved_path" == "$affected_path" ]] || printf '    resolved: %s\n' "$resolved_path"
        printf '    kind: %s\n' "$target_kind"
        printf '    reason: %s\n' "$reason"
        printf '    quarantine: %s\n' "$qtn_value"
        printf '    flags: 0x%04X (%s)\n' "$qtn_flags" "$flag_description"
        printf '    codesign: %s - %s\n' "$codesign_status" "$codesign_detail"
        printf '    gatekeeper: %s - %s\n' "$gatekeeper_status" "$gatekeeper_detail"
    done <<< "$details"
}

print_findings() {
    local finding_total=${#FINDING_ROOTS[@]}
    local index
    local actionable_artifact_count=0
    local actionable_path_count=0
    local informational_path_count=0
    local artifact_label
    local display_index
    local detail_filter

    for (( index=1; index<=finding_total; index++ )); do
        if [[ "${FINDING_CLASSES[$index]}" == "actionable" ]]; then
            actionable_artifact_count=$(( actionable_artifact_count + 1 ))
            actionable_path_count=$(( actionable_path_count + FINDING_ACTIONABLE_COUNTS[$index] ))
        fi
        informational_path_count=$(( informational_path_count + FINDING_INFORMATIONAL_COUNTS[$index] ))
    done

    if [[ "$finding_total" -eq 0 ]]; then
        success "No Homebrew quarantine findings detected."
        return 0
    fi

    if [[ "$actionable_artifact_count" -gt 0 ]]; then
        highlight "Found ${actionable_artifact_count} actionable Homebrew quarantine finding(s) covering ${actionable_path_count} path(s)."
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

    local informational_finding_count=0
    for (( index=1; index<=finding_total; index++ )); do
        [[ "${FINDING_CLASSES[$index]}" == "informational" ]] || continue
        informational_finding_count=$(( informational_finding_count + 1 ))
    done

    # Gate on there being informational *findings* to list, not merely
    # informational paths: those can all sit under an actionable finding, in
    # which case the loop below prints nothing and the header is just noise.
    if (( informational_finding_count > 0 )); then
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

# When no fix ran, say so explicitly in the log rather than leaving the initial
# placeholder, so a declined prompt and a dry run are distinguishable from a run
# that attempted a fix and did nothing.
mark_outcomes_unattempted() {
    local index

    for (( index=1; index<=${#FINDING_OUTCOMES[@]}; index++ )); do
        [[ "${FINDING_OUTCOMES[$index]}" == "not-attempted" ]] || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            FINDING_OUTCOMES[index]="dry-run"
        else
            FINDING_OUTCOMES[index]="declined"
        fi
    done
}

count_actionable_paths() {
    local total=0
    local index

    for (( index=1; index<=${#FINDING_CLASSES[@]}; index++ )); do
        [[ "${FINDING_CLASSES[$index]}" == "actionable" ]] || continue
        total=$(( total + FINDING_ACTIONABLE_COUNTS[index] ))
    done

    printf '%d\n' "$total"
}

confirm_fix() {
    local actionable=$1
    local actionable_paths=$2
    local response

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode enabled; exiting..."
        return 1
    fi

    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi

    printf '\nRemove com.apple.quarantine from %s path(s) across %s actionable finding(s)? [Y/n]: ' \
        "$actionable_paths" "$actionable"
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

# Strip the attribute from every listed path using as few processes as possible.
# xargs batches roughly a thousand paths per xattr invocation, which turns the
# ~5.7k individual calls a cask like codeql needed into a handful. Only the
# listed paths are touched, so user-approved informational records are still
# left alone.
remove_targets_batched() {
    local targets_file=$1

    /usr/bin/tr '\n' '\0' < "$targets_file" \
        | /usr/bin/xargs -0 /usr/bin/xattr -d com.apple.quarantine 2>/dev/null \
        || true
}

# Report which attempted targets still carry the attribute. A single recursive
# listing covers every target under the artifact root; targets that resolved
# outside it (e.g. an .app symlinked into /Applications) are checked one at a
# time, and there are normally only a handful of those.
collect_remaining_targets() {
    local artifact_root=$1
    local targets_file=$2
    local remaining_file=$3
    local inside_file="$TEMP_DIR/remaining-inside"
    local classified_file="$TEMP_DIR/remaining-classified"
    local remaining_fd
    local target

    : > "$inside_file"

    /usr/bin/xattr -r -l "$artifact_root" 2>/dev/null \
        | LC_ALL=C /usr/bin/awk -F': com.apple.quarantine: ' 'NF > 1 { print $1 }' \
        > "$inside_file" || true

    # Split the attempted targets into those the recursive listing still reports
    # as quarantined and those that resolved outside the artifact root and so
    # have to be probed individually.
    LC_ALL=C /usr/bin/awk -v root_prefix="${artifact_root}/" '
        NR == FNR { inside[$0] = 1; next }
        NF == 0 { next }
        $0 in inside { print "remaining\t" $0; next }
        index($0, root_prefix) != 1 { print "check\t" $0 }
    ' "$inside_file" "$targets_file" > "$classified_file"

    LC_ALL=C /usr/bin/awk -F'\t' '$1 == "remaining" { print $2 }' "$classified_file" > "$remaining_file"

    exec {remaining_fd}>>"$remaining_file"
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        if /usr/bin/xattr -p com.apple.quarantine "$target" >/dev/null 2>&1; then
            printf '%s\n' "$target" >&$remaining_fd
        fi
    done < <(LC_ALL=C /usr/bin/awk -F'\t' '$1 == "check" { print $2 }' "$classified_file")
    exec {remaining_fd}>&-
}

# Retry one path at a time. This is where the owner/sudo handling and the
# diagnostics live, so it stays the fallback for whatever the batch call could
# not clear rather than the default path.
remove_targets_individually() {
    local artifact_index=$1
    local targets_file=$2
    local fix_target
    local fix_owner
    local failure_count=0
    local shown_count=0
    local root_owned=false

    while IFS= read -r fix_target; do
        [[ -n "$fix_target" ]] || continue
        xattr_remove_as_owner "$fix_target" && continue

        failure_count=$(( failure_count + 1 ))
        fix_owner="$(/usr/bin/stat -f '%Su' "$fix_target" 2>/dev/null || true)"
        [[ "$fix_owner" == "root" ]] && root_owned=true

        if (( shown_count < FAILURE_SAMPLE_LIMIT )); then
            print_colored "$COLOR_RED" "Failed to remove quarantine from ${fix_target}"
            shown_count=$(( shown_count + 1 ))
        fi
    done < "$targets_file"

    (( failure_count == 0 )) && return 0

    if (( failure_count > shown_count )); then
        print_colored "$COLOR_RED" "...and $(( failure_count - shown_count )) further path(s)"
    fi

    # On macOS 26+ (or MDM-managed Macs), the bundle directory may be protected
    # from xattr modification even by root. Ownership and xattr changes require
    # going through macOS or Homebrew mechanisms.
    if [[ "$root_owned" == "true" ]]; then
        info "  Path(s) owned by root; quarantine removal is blocked by macOS 26+ protections."
        info "  Approve in System Settings > Privacy & Security (scroll to bottom) — or:"
        if [[ "${FINDING_TYPES[$artifact_index]}" == "cask" ]]; then
            info "  Reinstall with: brew reinstall --cask ${FINDING_NAMES[$artifact_index]}"
        fi
    fi

    return 1
}

fix_findings() {
    local index
    local artifact_label
    local success_count=0
    local failure_count=0
    local target_count
    local remaining_count
    local targets_file="$TEMP_DIR/fix-targets"
    local remaining_file="$TEMP_DIR/fix-remaining"

    for (( index=1; index<=${#FINDING_ROOTS[@]}; index++ )); do
        [[ "${FINDING_CLASSES[$index]}" == "actionable" ]] || continue

        artifact_label="$(artifact_label_at "$index")"
        printf '%s\n' "${FINDING_FIX_TARGETS[$index]}" > "$targets_file"
        target_count=$(/usr/bin/grep -c . "$targets_file" || true)
        target_count=$(( target_count ))

        highlight "Fixing ${artifact_label} (${target_count} path(s))"
        (( target_count > 0 )) || continue

        progress "Removing quarantine from ${target_count} path(s)"
        remove_targets_batched "$targets_file"
        collect_remaining_targets "${FINDING_ROOTS[$index]}" "$targets_file" "$remaining_file"
        progress_done

        remaining_count=$(/usr/bin/grep -c . "$remaining_file" || true)
        remaining_count=$(( remaining_count ))

        if (( remaining_count == 0 )); then
            success "Removed quarantine from all ${target_count} target(s) for ${artifact_label}"
            success_count=$(( success_count + 1 ))
            FINDING_OUTCOMES[index]="fixed"
            continue
        fi

        info "${remaining_count} path(s) still quarantined after the batch removal; retrying individually."
        if remove_targets_individually "$index" "$remaining_file"; then
            success "Removed quarantine from all ${target_count} target(s) for ${artifact_label}"
            success_count=$(( success_count + 1 ))
            FINDING_OUTCOMES[index]="fixed"
        else
            failure_count=$(( failure_count + 1 ))
            FINDING_OUTCOMES[index]="failed"
        fi
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

# Append one tab-separated line per finding. Opt-in via --log so the script stays
# side-effect free for anyone who just runs it, and so the history is only built
# where it was asked for. Columns:
#   timestamp  mode  type  name  version  kinds  paths  actionable  informational
#   outcome  reasons
write_log() {
    local log_dir="${LOG_FILE:h}"
    local log_fd
    local timestamp
    local mode
    local index
    local outcome

    [[ "$WRITE_LOG" == "true" ]] || return 0
    (( ${#FINDING_ROOTS[@]} > 0 )) || return 0

    if ! /bin/mkdir -p "$log_dir" 2>/dev/null; then
        info "Could not create log directory ${log_dir}; skipping log."
        return 0
    fi

    timestamp="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "$DRY_RUN" == "true" ]]; then
        mode="dry-run"
    elif [[ "$ASSUME_YES" == "true" ]]; then
        mode="assume-yes"
    else
        mode="prompted"
    fi

    # Probe with touch rather than letting the exec redirection fail: zsh prints
    # its own "permission denied" for a failed redirection, which 2>/dev/null on
    # the exec does not suppress.
    if ! /usr/bin/touch "$LOG_FILE" 2>/dev/null; then
        info "Could not write ${LOG_FILE}; skipping log."
        return 0
    fi

    exec {log_fd}>>"$LOG_FILE"

    for (( index=1; index<=${#FINDING_ROOTS[@]}; index++ )); do
        if [[ "${FINDING_CLASSES[$index]}" == "informational" ]]; then
            outcome="informational"
        else
            outcome="${FINDING_OUTCOMES[$index]}"
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$timestamp" \
            "$mode" \
            "${FINDING_TYPES[$index]}" \
            "${FINDING_NAMES[$index]}" \
            "${FINDING_VERSIONS[$index]}" \
            "${FINDING_KINDS[$index]:--}" \
            "${FINDING_COUNTS[$index]}" \
            "${FINDING_ACTIONABLE_COUNTS[$index]}" \
            "${FINDING_INFORMATIONAL_COUNTS[$index]}" \
            "$outcome" \
            "${FINDING_REASONS[$index]:--}" >&$log_fd
    done

    exec {log_fd}>&-
    info "Logged ${#FINDING_ROOTS[@]} finding(s) to ${LOG_FILE}"
}

main() {
    parse_args "$@"

    require_command brew
    require_command xattr
    require_command find
    require_command awk
    require_command grep
    require_command mktemp
    require_command sort
    require_command stat
    require_command tr
    require_command wc
    require_command xargs
    require_command touch

    # Traps are installed immediately after the scratch directory exists so an
    # interrupted scan — easy to trigger, since a large cask takes a while — does
    # not leave temp files behind.
    TEMP_DIR="$(mktemp -d /tmp/brew-quarantine.XXXXXX)"
    trap 'cleanup' EXIT
    trap 'cleanup; exit 130' INT
    trap 'cleanup; exit 143' TERM

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
    local actionable_paths
    actionable="$(count_actionable)"

    if [[ "$actionable" -gt 0 ]]; then
        actionable_paths="$(count_actionable_paths)"
        if confirm_fix "$actionable" "$actionable_paths"; then
            fix_findings
        else
            mark_outcomes_unattempted
        fi
    fi

    write_log
}

main "$@"
