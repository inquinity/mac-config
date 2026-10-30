#!/bin/zsh
#
# brew-receipt-audit.sh
#
# Find Homebrew formulae whose install receipt (INSTALL_RECEIPT.json) still
# records a runtime dependency the formula no longer needs, reinstall them so
# the receipt is rewritten, and offer to uninstall dependencies that nothing
# needs any more.
#
# Why this exists: a receipt's runtime_dependencies are written once, at
# install time, and only rewritten when that formula itself is reinstalled.
# When a dependency changes underneath it -- simdutf moving from icu4c@78 to
# icu4c@79, say -- the dependents keep the old entry. `brew uses --installed`,
# `brew autoremove` and `brew doctor` all read receipts, so the old keg stays
# "in use" and cannot be cleaned up even though no binary links against it.
#
# A recorded dependency is reported as stale only when all of these hold:
#   - it is not in the formula's declared dependency tree (current formula
#     definitions, followed recursively),
#   - it is not in the receipt of any of the formula's direct dependencies,
#   - the formula's keg does not link against it (`brew linkage`), and
#   - it is still installed (a missing one is `brew missing`'s business).
# The linkage check matters on machines whose formula API comes from a mirror:
# a mirror's JSON can omit a dependency the formula really has, and without the
# check that dependency would be reported, and later removed, by mistake.
#
# Outdated formulae are reported but never reinstalled: `brew reinstall`
# installs the newest version, so reinstalling one would quietly upgrade it and
# sidestep brew-safe.sh's cool-off. They are left for the next upgrade.

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

PROGRAM_NAME="${0:t}"
ASSUME_YES=false
DRY_RUN=false
QUIET=false
WRITE_LOG=false
LOG_FILE="${HOME}/Library/Logs/brew-receipt-audit.log"

# A reinstall can expose a further stale receipt: when a dependency's own
# receipt was stale, its dependents inherit that entry and are only flagged
# once the dependency has been rewritten. A few passes settle any realistic
# chain; the limit only guards against a reinstall that changes nothing.
typeset -i MAX_PASSES=3

typeset -a FINDING_FORMULAE   # formula with a stale receipt
typeset -a FINDING_DEPS       # its stale dependencies, comma-separated
typeset -a FINDING_OUTDATED   # "true" when the formula is outdated
typeset -a FINDING_OUTDATED_DEPS  # its outdated dependencies, comma-separated
typeset -a FINDING_OUTCOMES   # filled in as findings are handled; used by the log
typeset -a FINDING_LOG        # every pass's findings, kept for the log
typeset -a REINSTALLED        # formulae already reinstalled this run
typeset -a STALE_DEPS         # every stale dependency seen this run
typeset -a REMOVED_DEPS       # dependencies uninstalled this run

# Emits one line per formula with a stale receipt:
#   formula <TAB> stale,deps <TAB> outdated <TAB> outdated,deps
# The last column names installed dependencies (from the receipt) that are
# outdated: `brew reinstall` upgrades those too, so the formula is skipped.
# Input is `brew info --json=v2 --installed`; $linkage is the formula<TAB>library
# pairs parsed from `brew linkage`.
STALE_RECEIPTS_JQ='
def strip_core: sub("^homebrew/core/"; "");
.formulae as $all
| ([$all[] | .full_name as $full | (.aliases + .oldnames + [.name, .full_name])[]
    | {key: strip_core, value: $full}] | from_entries) as $canon
| def canon: strip_core as $name | ($canon[$name] // $name);
  ([$all[] | {key: .full_name, value: .}] | from_entries) as $by_name
| ($linkage | split("\n") | map(select(length > 0) | split("\t")) | group_by(.[0])
    | map({key: (.[0][0] | canon), value: map(.[1] | canon)}) | from_entries) as $links
| def keg: . as $formula
      | ((.installed | map(select(.version == $formula.linked_keg)) | first) // .installed[-1]);
  def receipt: keg.runtime_dependencies | if . == null then null else map(.full_name | canon) end;
  def declared: [(.dependencies + .recommended_dependencies + .optional_dependencies)[] | canon]
      + [.uses_from_macos[]?
         | if type == "string" then . else to_entries[] | select(.value != "build" and .value != "test") | .key end
         | canon];
  def closure($seen): reduce declared[] as $dep ($seen;
      if index([$dep]) then .
      else (. + [$dep]) as $next | ($by_name[$dep] | if . == null then $next else closure($next) end)
      end);
$all[]
| . as $formula
| ($formula | receipt) as $recorded
| select($recorded != null)
| ($formula | declared) as $direct
| (($formula | closure([]))
    + [$direct[] | ($by_name[.] // empty) | receipt // [] | .[]]
    + ($links[$formula.full_name] // [])) as $expected
| [($recorded - $expected)[] | select($by_name[.] != null)] | unique
| select(length > 0)
| [$formula.full_name, join(","), ($formula.outdated | tostring),
   ([$recorded[] | select($by_name[.].outdated == true)] | unique | join(","))] | @tsv
'

# Emits each of $targets that nothing needs any more: installed as a dependency
# rather than on request, absent from every other formula's receipt and
# declared dependencies and from every cask's formula dependencies, and not
# linked against by any other keg. Input needs casks too, so the caller uses
# `brew info --json=v2 --installed` (formulae and casks).
UNNEEDED_DEPS_JQ='
def strip_core: sub("^homebrew/core/"; "");
.formulae as $all
| ([$all[] | .full_name as $full | (.aliases + .oldnames + [.name, .full_name])[]
    | {key: strip_core, value: $full}] | from_entries) as $canon
| def canon: strip_core as $name | ($canon[$name] // $name);
  ($linkage | split("\n") | map(select(length > 0) | split("\t") | map(canon))) as $links
| [.casks[]? | .depends_on.formula // [] | if type == "string" then [.] else . end | .[] | canon] as $cask_deps
| $targets | split(",")[] as $target
| ($all | map(select(.full_name == $target)) | first) as $formula
| select($formula != null)
| select(($formula.installed | map(.installed_on_request) | any) | not)
| select([$all[] | select(.full_name != $target)
          | (.installed[].runtime_dependencies // [] | .[].full_name),
            (.dependencies + .recommended_dependencies + .optional_dependencies)[]
          | canon] | index([$target]) | not)
| select($cask_deps | index([$target]) | not)
| select([$links[] | select(.[0] != $target and .[1] == $target)] | length == 0)
| $target
'

usage() {
    cat <<EOF
Usage: ${PROGRAM_NAME} [options]

Find Homebrew formulae whose install receipt records a runtime dependency they
no longer need, reinstall them so the receipt is rewritten, and offer to
uninstall dependencies that nothing needs any more.

Options:
  -y, --yes              Reinstall without prompting. Uninstalling a freed
                         dependency always asks, so --yes only lists those
  -n, --dry-run          Show findings and the commands that would run, but
                         do not change anything
  -q, --quiet            Print nothing when there are no stale receipts
  -l, --log [FILE]       Append one tab-separated line per finding and removal
                         to FILE (default: ~/Library/Logs/brew-receipt-audit.log)
  -h, --help             Show this help text

Exit status is 0 when no stale receipts remain, 1 when some do (declined,
outdated, or failed), and 2 on a usage, environment or brew/jq error.

Examples:
  ${PROGRAM_NAME}
  ${PROGRAM_NAME} --dry-run
  ${PROGRAM_NAME} --quiet --log
EOF
}

die() {
    # stderr, so the message survives when die runs inside a $( ) capture.
    print_colored "$COLOR_RED" "ERROR: $1" >&2
    exit 2
}

info() {
    [[ "$QUIET" == "true" && "${2:-}" != "always" ]] && return 0
    print_colored "$COLOR_YELLOW" "$1"
}

success() {
    print_colored "$COLOR_GREEN" "$1"
}

highlight() {
    print_colored "$COLOR_BRIGHTYELLOW" "$1"
}

warn() {
    print_colored "$COLOR_RED" "$1"
}

require_command() {
    local command_name=$1
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                ASSUME_YES=true
                ;;
            -n|--dry-run)
                DRY_RUN=true
                ;;
            -q|--quiet)
                QUIET=true
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
                usage >&2
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

# formula<TAB>library-formula pairs from `brew linkage`, one per line. Lines
# under "Missing libraries:" are skipped: a missing library is not a link.
collect_linkage() {
    local linkage_output
    linkage_output="$(brew linkage 2>/dev/null)" || die "brew linkage failed"
    printf '%s\n' "$linkage_output" | awk '
        /^==> Checking .* linkage$/ { formula = $3; section = ""; next }
        /^[^ ]/                     { section = $0; next }
        section !~ /^Missing/ && match($0, /\([^()]+\)$/) {
            print formula "\t" substr($0, RSTART + 1, RLENGTH - 2)
        }' | sort -u
}

# Fill the FINDING_* arrays from the current state of the Cellar.
scan_for_findings() {
    local installed_json linkage findings formula deps outdated outdated_deps

    installed_json="$(brew info --json=v2 --installed)" || die "brew info failed"
    linkage="$(collect_linkage)" || exit 2
    # Captured rather than read from a process substitution, whose failure
    # errexit cannot see: a jq error must not look like "nothing stale".
    findings="$(jq -r --arg linkage "$linkage" "$STALE_RECEIPTS_JQ" <<<"$installed_json")" \
        || die "jq failed while reading brew info output"

    FINDING_FORMULAE=()
    FINDING_DEPS=()
    FINDING_OUTDATED=()
    FINDING_OUTDATED_DEPS=()
    FINDING_OUTCOMES=()
    while IFS=$'\t' read -r formula deps outdated outdated_deps; do
        [[ -n "$formula" ]] || continue
        FINDING_FORMULAE+=("$formula")
        FINDING_DEPS+=("$deps")
        FINDING_OUTDATED+=("$outdated")
        FINDING_OUTDATED_DEPS+=("$outdated_deps")
        FINDING_OUTCOMES+=("reported")
        STALE_DEPS+=("${(@s:,:)deps}")
    done <<<"$findings"
    STALE_DEPS=("${(@u)STALE_DEPS}")
}

print_findings() {
    local index

    (( ${#FINDING_FORMULAE[@]} > 0 )) || return 0
    highlight "Stale Homebrew receipts:"
    for (( index=1; index<=${#FINDING_FORMULAE[@]}; index++ )); do
        if [[ "${FINDING_OUTDATED[$index]}" == "true" ]]; then
            info "  ${FINDING_FORMULAE[$index]}: ${FINDING_DEPS[$index]//,/, } (outdated; left for the next upgrade)" always
        elif [[ -n "${FINDING_OUTDATED_DEPS[$index]}" ]]; then
            info "  ${FINDING_FORMULAE[$index]}: ${FINDING_DEPS[$index]//,/, } (depends on outdated ${FINDING_OUTDATED_DEPS[$index]//,/, }; left for the next upgrade)" always
        else
            info "  ${FINDING_FORMULAE[$index]}: ${FINDING_DEPS[$index]//,/, }" always
        fi
    done
}

# Ask a yes/no question. $2 is the answer an empty response means. Without a
# terminal there is nobody to ask, so the answer is no unless --yes was given.
confirm() {
    local question=$1
    local default_answer=$2
    local prompt_hint response

    [[ "$ASSUME_YES" == "true" ]] && return 0
    if [[ ! -t 0 ]]; then
        info "No terminal to confirm on; no changes made (use --yes)." always
        return 1
    fi

    [[ "$default_answer" == "yes" ]] && prompt_hint="[Y/n]" || prompt_hint="[y/N]"
    printf '%s %s: ' "$question" "$prompt_hint"
    # End of input (Ctrl-D) is a no, not the default answer.
    IFS= read -r response || { printf '\n'; return 1; }
    case "$response" in
        "") [[ "$default_answer" == "yes" ]] ;;
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

set_outcome() {
    local formula=$1
    local outcome=$2
    local index

    for (( index=1; index<=${#FINDING_FORMULAE[@]}; index++ )); do
        [[ "${FINDING_FORMULAE[$index]}" == "$formula" ]] && FINDING_OUTCOMES[$index]="$outcome"
    done
    return 0
}

# Reinstall every finding that is safe to reinstall. Returns 1 when nothing
# was reinstalled (nothing to do, declined, or dry run), so the caller knows
# another pass would find the same thing.
reinstall_findings() {
    local -a targets
    local index formula

    for (( index=1; index<=${#FINDING_FORMULAE[@]}; index++ )); do
        formula="${FINDING_FORMULAE[$index]}"
        if [[ "${FINDING_OUTDATED[$index]}" == "true" ]]; then
            FINDING_OUTCOMES[$index]="skipped-outdated"
        elif [[ -n "${FINDING_OUTDATED_DEPS[$index]}" ]]; then
            FINDING_OUTCOMES[$index]="skipped-outdated-dep"
        elif (( ${REINSTALLED[(Ie)$formula]} )); then
            # Already reinstalled this run and still stale: another reinstall
            # will not help, so stop rather than loop.
            FINDING_OUTCOMES[$index]="still-stale"
        else
            targets+=("$formula")
        fi
    done
    (( ${#targets[@]} > 0 )) || return 1

    if [[ "$DRY_RUN" == "true" ]]; then
        highlight "Would run: brew reinstall --formula ${targets[*]}"
        for formula in "${targets[@]}"; do set_outcome "$formula" "dry-run"; done
        return 1
    fi

    if ! confirm "Reinstall ${#targets[@]} formula(e) to rewrite their receipts?" yes; then
        info "No formulae reinstalled." always
        for formula in "${targets[@]}"; do set_outcome "$formula" "declined"; done
        return 1
    fi

    highlight "Running: brew reinstall --formula ${targets[*]}"
    REINSTALLED+=("${targets[@]}")
    # Without this, brew reinstall also upgrades outdated dependents of the
    # targets -- the cool-off bypass the outdated checks above exist to avoid.
    if HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew reinstall --formula "${targets[@]}"; then
        for formula in "${targets[@]}"; do set_outcome "$formula" "reinstalled"; done
    else
        warn "brew reinstall failed; see the output above."
        for formula in "${targets[@]}"; do set_outcome "$formula" "failed"; done
        return 1
    fi
}

# Offer to uninstall stale dependencies that nothing needs any more. Each
# uninstall is checked against fresh receipts and linkage, so a dependency
# still used by anything else is left alone.
remove_unneeded_deps() {
    local -a candidates
    local installed_json linkage dep

    (( ${#STALE_DEPS[@]} > 0 )) || return 0
    local candidate_list
    installed_json="$(brew info --json=v2 --installed)" || die "brew info failed"
    linkage="$(collect_linkage)" || exit 2
    candidate_list="$(jq -r --arg linkage "$linkage" --arg targets "${(j:,:)STALE_DEPS}" \
        "$UNNEEDED_DEPS_JQ" <<<"$installed_json")" || die "jq failed while reading brew info output"
    candidates=("${(@f)candidate_list}")
    candidates=("${(@)candidates:#}")
    (( ${#candidates[@]} > 0 )) || return 0

    highlight "No longer needed by any installed formula: ${candidates[*]}"
    if [[ "$DRY_RUN" == "true" ]]; then
        highlight "Would run: brew uninstall --formula ${candidates[*]}"
        return 0
    fi
    # Receipts and linkage cannot see everything a dependency is used for (an
    # interpreter a venv points at, an exec'd tool), so removal is always the
    # user's call: --yes reinstalls but never uninstalls.
    if [[ "$ASSUME_YES" == "true" ]]; then
        info "Not uninstalled under --yes; run ${PROGRAM_NAME} interactively or 'brew uninstall' them." always
        return 0
    fi
    if ! confirm "Uninstall them?" no; then
        info "Nothing uninstalled. 'brew autoremove' will offer them again later." always
        return 0
    fi

    highlight "Running: brew uninstall --formula ${candidates[*]}"
    if brew uninstall --formula "${candidates[@]}"; then
        REMOVED_DEPS+=("${candidates[@]}")
    else
        warn "brew uninstall failed; see the output above."
    fi
}

# Append one tab-separated line per finding and removal. Opt-in via --log so the
# script stays side-effect free for anyone who just runs it. Columns:
#   timestamp  mode  kind  name  stale-deps  outcome
# kind is "receipt" for a stale receipt and "removal" for an uninstalled
# dependency; outcome is one of reported, reinstalled, failed, declined,
# dry-run, skipped-outdated, skipped-outdated-dep, still-stale or removed.
write_log() {
    local log_dir="${LOG_FILE:h}"
    local log_fd timestamp mode index dep

    [[ "$WRITE_LOG" == "true" ]] || return 0
    (( ${#FINDING_LOG[@]} + ${#REMOVED_DEPS[@]} > 0 )) || return 0

    if ! /bin/mkdir -p "$log_dir" 2>/dev/null || ! /usr/bin/touch "$LOG_FILE" 2>/dev/null; then
        info "Could not write ${LOG_FILE}; skipping log." always
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

    exec {log_fd}>>"$LOG_FILE"
    for (( index=1; index<=${#FINDING_LOG[@]}; index++ )); do
        printf '%s\t%s\t%s\n' "$timestamp" "$mode" "${FINDING_LOG[$index]}" >&$log_fd
    done
    for dep in "${REMOVED_DEPS[@]}"; do
        printf '%s\t%s\tremoval\t%s\t-\tremoved\n' "$timestamp" "$mode" "$dep" >&$log_fd
    done
    exec {log_fd}>&-
    info "Logged to ${LOG_FILE}"
}

# Keep each pass's findings for the log before the next scan replaces them.
record_findings_for_log() {
    local index
    for (( index=1; index<=${#FINDING_FORMULAE[@]}; index++ )); do
        FINDING_LOG+=("receipt"$'\t'"${FINDING_FORMULAE[$index]}"$'\t'"${FINDING_DEPS[$index]}"$'\t'"${FINDING_OUTCOMES[$index]}")
    done
}

main() {
    local -i pass=1

    parse_args "$@"

    require_command brew
    require_command jq
    require_command awk
    require_command sort

    [[ "$DRY_RUN" == "true" ]] && info "Dry run mode enabled. No changes will be made."

    scan_for_findings
    if (( ${#FINDING_FORMULAE[@]} == 0 )); then
        info "No stale Homebrew receipts."
        return 0
    fi

    # Each pass reinstalls what it can and rescans, so the loop ends with the
    # FINDING_* arrays holding whatever is still stale.
    while true; do
        print_findings
        if ! reinstall_findings; then
            record_findings_for_log
            break
        fi
        record_findings_for_log
        scan_for_findings
        (( ${#FINDING_FORMULAE[@]} > 0 )) || break
        if (( ++pass > MAX_PASSES )); then
            print_findings
            record_findings_for_log
            break
        fi
        info "Reinstalling exposed further stale receipts; checking again."
    done

    remove_unneeded_deps
    write_log

    (( ${#FINDING_FORMULAE[@]} == 0 )) || return 1
    success "Homebrew receipts are up to date."
}

main "$@"
