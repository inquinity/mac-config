#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.0
#
# Purpose:
# Wrapper around the CodeQL CLI. Creates (or refreshes) a CodeQL database for
# the current source tree, then analyzes it against the standard security query
# suites, resolving the .qls suite paths inside a local checkout of the
# github/codeql repository.
#
# The query suite directories in that checkout use short language names
# (cpp, java, javascript) rather than the hyphenated code-scanning identifiers
# (c-cpp, java-kotlin, javascript-typescript). Both forms are accepted on the
# command line and resolve to the short name.
#
# Suites are passed to "database analyze" by bare name together with
# --search-path, not as a filesystem path, for two reasons:
#   1. A source checkout declares its pack dependencies as ${workspace}, which
#      only resolves when the checkout root is on the search path. Given a bare
#      path the analysis fails with "pack was not found in the workspace".
#   2. CodeQL splits a query specification on "@" to separate pack from version,
#      so any path containing "@" (a home directory such as
#      /Users/first.last@example.com) is rejected as an invalid package
#      specification.
# The full path is still checked on disk first, so a bad suite or language name
# fails immediately instead of after a long database build.
#
# Requirements:
# 1. codeql CLI on PATH
#    https://github.com/github/codeql-cli-binaries/releases
#    Override the binary with the CODEQL_CLI variable if it is not on PATH.
# 2. A local checkout of github/codeql supplying the query suites.
#    Defaults to ~/dev/codeql; override with the CODEQL_REPO variable.

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
    printf '%b%s%b\n' "${color}" "${message}" "${COLOR_RESET}"
}

SCRIPT_NAME="${0##*/}"
SCRIPT_PATH="${0:A}"

# Local checkout of github/codeql that supplies the .qls query suites
CODEQL_REPO="${CODEQL_REPO:-$HOME/dev/codeql}"

# The CodeQL CLI binary. "codeql" is often aliased to this wrapper in an
# interactive shell, so allow an explicit path to the real CLI.
CODEQL_CLI="${CODEQL_CLI:-codeql}"

# Defaults, each overridable by an option below
DATABASE_PATH=".codeqlDB"
OUTPUT_DIRECTORY="codeqlAnalysis"
OUTPUT_FORMAT="sarif-latest"
OUTPUT_EXTENSION="sarif"
THREAD_COUNT="0"
SOURCE_ROOT="."
SUITE_SELECTION="all"
BUILD_MODE=""        # empty means "use the per-language default"
BUILD_COMMAND=""     # non-empty switches database create to a manual build
CREATE_DATABASE=1
CLEAN_ONLY=0
DRY_RUN=0

# Accepted language spellings mapped to the name used by both the CodeQL CLI
# and the query suite directory layout.
typeset -A LANGUAGE_ALIASES=(
    c                     cpp
    c++                   cpp
    cpp                   cpp
    c-cpp                 cpp
    csharp                csharp
    'c#'                  csharp
    go                    go
    golang                go
    java                  java
    kotlin                java
    java-kotlin           java
    js                    javascript
    javascript            javascript
    ts                    javascript
    typescript            javascript
    javascript-typescript javascript
    py                    python
    python                python
    rb                    ruby
    ruby                  ruby
    swift                 swift
)

# Build mode used by "database create" when none is given explicitly.
#
# "none" extracts straight from source and so works on any tree, including one
# with no build system. "autobuild" needs a working build and fails outright
# without one, which makes it a poor default. Verified against CodeQL 2.27.2:
# go and swift reject "none" outright ("Go does not support the none build
# mode"), so they must use autobuild; every other language here accepts it.
#
# The trade-off for a compiled language: "none" skips dependency resolution, so
# results are less precise than a real build. Pass --build-mode autobuild, or
# --command with the build, when scanning a project that does build.
typeset -A DEFAULT_BUILD_MODES=(
    cpp        none
    csharp     none
    java       none
    javascript none
    python     none
    ruby       none
    go         autobuild
    swift      autobuild
)

usage() {
    print_colored "${COLOR_YELLOW}" "Usage: ${SCRIPT_NAME} [options] <language>"
    print_colored "${COLOR_YELLOW}" ""
    print_colored "${COLOR_YELLOW}" "Creates a CodeQL database for the current directory, then analyzes it"
    print_colored "${COLOR_YELLOW}" "against the security query suites and writes one report per suite into"
    print_colored "${COLOR_YELLOW}" "./${OUTPUT_DIRECTORY}/."
    print_colored "${COLOR_YELLOW}" ""
    print_colored "${COLOR_YELLOW}" "Languages (any spelling in a row is accepted):"
    print_colored "${COLOR_YELLOW}" "  c, cpp, c++, c-cpp                            -> cpp"
    print_colored "${COLOR_YELLOW}" "  csharp, c#                                    -> csharp"
    print_colored "${COLOR_YELLOW}" "  go, golang                                    -> go"
    print_colored "${COLOR_YELLOW}" "  java, kotlin, java-kotlin                     -> java"
    print_colored "${COLOR_YELLOW}" "  js, javascript, ts, typescript,"
    print_colored "${COLOR_YELLOW}" "    javascript-typescript                       -> javascript"
    print_colored "${COLOR_YELLOW}" "  py, python                                    -> python"
    print_colored "${COLOR_YELLOW}" "  rb, ruby                                      -> ruby"
    print_colored "${COLOR_YELLOW}" "  swift                                         -> swift"
    print_colored "${COLOR_YELLOW}" ""
    print_colored "${COLOR_YELLOW}" "Options:"
    print_colored "${COLOR_YELLOW}" "  --format <fmt>      sarif (default) or csv"
    print_colored "${COLOR_YELLOW}" "  --suite <list>      comma-separated suites to run (default: all)"
    print_colored "${COLOR_YELLOW}" "                        all        security-extended and security-and-quality"
    print_colored "${COLOR_YELLOW}" "                        extended   security-extended"
    print_colored "${COLOR_YELLOW}" "                        quality    security-and-quality"
    print_colored "${COLOR_YELLOW}" "                      any other value is used as a literal suite name,"
    print_colored "${COLOR_YELLOW}" "                      for example code-scanning or security-experimental"
    print_colored "${COLOR_YELLOW}" "  --db <path>         database location (default: ${DATABASE_PATH})"
    print_colored "${COLOR_YELLOW}" "  --threads <n>       threads for create and analyze (default: ${THREAD_COUNT}, all cores)"
    print_colored "${COLOR_YELLOW}" "  --build-mode <mode> none, autobuild, or manual; overrides the language default."
    print_colored "${COLOR_YELLOW}" "                      Default is none, which needs no build system but is less"
    print_colored "${COLOR_YELLOW}" "                      precise for compiled languages; pass autobuild when the"
    print_colored "${COLOR_YELLOW}" "                      project builds. go and swift do not support none and"
    print_colored "${COLOR_YELLOW}" "                      default to autobuild."
    print_colored "${COLOR_YELLOW}" "  --command <cmd>     build command for a compiled language; implies a manual build"
    print_colored "${COLOR_YELLOW}" "  --no-create         analyze the existing database instead of rebuilding it"
    print_colored "${COLOR_YELLOW}" "  --clean             remove the database and ./${OUTPUT_DIRECTORY}/, then exit"
    print_colored "${COLOR_YELLOW}" "  -n, --dry-run       print the codeql commands without running them"
    print_colored "${COLOR_YELLOW}" "  -h, --help          show this help"
    print_colored "${COLOR_YELLOW}" ""
    print_colored "${COLOR_YELLOW}" "Environment:"
    print_colored "${COLOR_YELLOW}" "  CODEQL_REPO         checkout supplying the query suites (default: ~/dev/codeql)"
    print_colored "${COLOR_YELLOW}" "  CODEQL_CLI          path to the CodeQL CLI (default: codeql, found on PATH)"
    print_colored "${COLOR_YELLOW}" ""
    print_colored "${COLOR_YELLOW}" "Examples:"
    print_colored "${COLOR_YELLOW}" "  ${SCRIPT_NAME} java                       # both suites, sarif"
    print_colored "${COLOR_YELLOW}" "  ${SCRIPT_NAME} --format csv js            # both suites, csv"
    print_colored "${COLOR_YELLOW}" "  ${SCRIPT_NAME} --suite extended python    # one suite"
    print_colored "${COLOR_YELLOW}" "  ${SCRIPT_NAME} --no-create java           # reuse the existing database"
    print_colored "${COLOR_YELLOW}" "  ${SCRIPT_NAME} --clean                    # delete database and reports"
    print_colored "${COLOR_YELLOW}" ""
    print_colored "${COLOR_YELLOW}" "Exit status: 0 success, 1 a codeql command failed, 2 usage or setup error."
}

# Abort with a usage-or-setup error.
# Writes to stderr so the message stays visible when this runs inside a command
# substitution, where "exit" ends only the subshell. The nonzero status then
# trips errexit in the caller.
fail_setup() {
    print_colored "${COLOR_RED}" "$1" >&2
    exit 2
}

# Confirm every required command is available before doing any work.
# A dry run only prints commands, so a missing CLI is a warning there, not a stop.
require_commands() {
    local resolved_cli
    resolved_cli="$(command -v "${CODEQL_CLI}" 2>/dev/null || true)"

    if [[ -z "${resolved_cli}" ]]; then
        if (( DRY_RUN )); then
            print_colored "${COLOR_RED}" "Warning: ${CODEQL_CLI} is not on PATH; this dry run only prints commands"
            return 0
        fi
        fail_setup "Required command not found: ${CODEQL_CLI}. Install the CodeQL CLI, or set CODEQL_CLI to its path."
    fi

    # Guard against this wrapper being installed on PATH as "codeql", which
    # would make every invocation below re-enter this script.
    if [[ "${resolved_cli:A}" == "${SCRIPT_PATH}" ]]; then
        fail_setup "${CODEQL_CLI} resolves to this wrapper (${resolved_cli}). Set CODEQL_CLI to the real CodeQL CLI."
    fi
}

# Reject a missing or empty value after an option
require_option_value() {
    local option_name=$1
    local option_value=$2
    [[ -n "${option_value}" ]] || fail_setup "Option ${option_name} requires a value"
}

# Map a user-supplied language spelling to its canonical name
resolve_language() {
    local requested_language="${1:l}"   # zsh: lowercase the argument
    local canonical_language="${LANGUAGE_ALIASES[${requested_language}]:-}"
    [[ -n "${canonical_language}" ]] ||
        fail_setup "Unsupported language: ${1}. Run ${SCRIPT_NAME} --help for the list."
    printf '%s' "${canonical_language}"
}

# Expand a suite shorthand into the suite name used in the .qls filename
resolve_suite_name() {
    case "$1" in
        extended) printf 'security-extended' ;;
        quality)  printf 'security-and-quality' ;;
        *)        printf '%s' "$1" ;;
    esac
}

# Bare suite specification, resolved by CodeQL against --search-path
suite_spec_for() {
    local canonical_language=$1
    local suite_name=$2
    printf '%s-%s.qls' "${canonical_language}" "${suite_name}"
}

# Absolute path of a language's query suite file, used only to verify it exists
suite_path_for() {
    local canonical_language=$1
    local suite_name=$2
    printf '%s/%s/ql/src/codeql-suites/%s-%s.qls' \
        "${CODEQL_REPO}" "${canonical_language}" "${canonical_language}" "${suite_name}"
}

# Echo a command, then run it unless this is a dry run
run_command() {
    print_colored "${COLOR_CYAN}" "  $*"
    if (( DRY_RUN )); then
        return 0
    fi
    "$@"
}

# Refuse to delete paths that are too broad to have been meant
validate_removal_target() {
    local removal_target=$1
    case "${removal_target}" in
        ''|'/'|'.'|'..'|'~'|"${HOME}"|"${HOME}/")
            fail_setup "Refusing to remove '${removal_target}': path is too broad"
            ;;
    esac
}

# Remove the database and the report directory
clean_artifacts() {
    local -a removal_targets=()
    local removal_target

    for removal_target in "${DATABASE_PATH}" "${OUTPUT_DIRECTORY}"; do
        validate_removal_target "${removal_target}"
        if [[ -e "${removal_target}" ]]; then
            removal_targets+=("${removal_target}")
        fi
    done

    if (( ${#removal_targets} == 0 )); then
        print_colored "${COLOR_YELLOW}" "Nothing to clean in $(pwd): no '${DATABASE_PATH}' and no '${OUTPUT_DIRECTORY}'"
        return 0
    fi

    print_colored "${COLOR_BRIGHTYELLOW}" "Removing:"
    for removal_target in "${removal_targets[@]}"; do
        run_command rm -rf -- "${removal_target}"
    done

    if (( DRY_RUN )); then
        print_colored "${COLOR_BRIGHTYELLOW}" "Dry run: nothing was removed"
    else
        print_colored "${COLOR_GREEN}" "Clean complete"
    fi
}

# Create or refresh the CodeQL database for the given language
create_database() {
    local canonical_language=$1
    local -a create_arguments=(
        database create "${DATABASE_PATH}"
        --language="${canonical_language}"
        --source-root="${SOURCE_ROOT}"
        --threads="${THREAD_COUNT}"
        --overwrite
    )

    # A build command is a manual build, so it replaces the build mode entirely
    if [[ -n "${BUILD_COMMAND}" ]]; then
        create_arguments+=(--command="${BUILD_COMMAND}")
    else
        local effective_build_mode="${BUILD_MODE:-${DEFAULT_BUILD_MODES[${canonical_language}]}}"
        create_arguments+=(--build-mode="${effective_build_mode}")
    fi

    print_colored "${COLOR_BRIGHTYELLOW}" "Creating database '${DATABASE_PATH}' for ${canonical_language}"
    run_command "${CODEQL_CLI}" "${create_arguments[@]}"
}

# Analyze the database against one suite, writing one report
analyze_suite() {
    local suite_name=$1
    local suite_spec=$2
    local output_file="${OUTPUT_DIRECTORY}/codeqlAnalysis_${suite_name}.${OUTPUT_EXTENSION}"

    print_colored "${COLOR_BRIGHTYELLOW}" "Analyzing ${suite_name} -> ${output_file}"
    run_command "${CODEQL_CLI}" database analyze "${DATABASE_PATH}" "${suite_spec}" \
        --search-path="${CODEQL_REPO}" \
        --threads="${THREAD_COUNT}" \
        --format="${OUTPUT_FORMAT}" \
        --output="${output_file}"
}

# Normalize "--option=value" into "--option" "value" so one parser handles both
typeset -a normalized_arguments=()
for raw_argument in "$@"; do
    if [[ "${raw_argument}" == --*=* ]]; then
        normalized_arguments+=("${raw_argument%%=*}" "${raw_argument#*=}")
    else
        normalized_arguments+=("${raw_argument}")
    fi
done
if (( ${#normalized_arguments} > 0 )); then
    set -- "${normalized_arguments[@]}"
fi

typeset -a positional_arguments=()
requested_format="sarif"

while (( $# > 0 )); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        --clean)
            CLEAN_ONLY=1
            shift
            ;;
        --no-create)
            CREATE_DATABASE=0
            shift
            ;;
        --format)
            require_option_value "$1" "${2-}"
            requested_format="$2"
            shift 2
            ;;
        --suite)
            require_option_value "$1" "${2-}"
            SUITE_SELECTION="$2"
            shift 2
            ;;
        --db)
            require_option_value "$1" "${2-}"
            DATABASE_PATH="$2"
            shift 2
            ;;
        --threads)
            require_option_value "$1" "${2-}"
            THREAD_COUNT="$2"
            shift 2
            ;;
        --build-mode)
            require_option_value "$1" "${2-}"
            BUILD_MODE="$2"
            shift 2
            ;;
        --command)
            require_option_value "$1" "${2-}"
            BUILD_COMMAND="$2"
            shift 2
            ;;
        --)
            shift
            positional_arguments+=("$@")
            break
            ;;
        -*)
            print_colored "${COLOR_RED}" "Unknown option: $1"
            usage
            exit 2
            ;;
        *)
            positional_arguments+=("$1")
            shift
            ;;
    esac
done

# --clean stands alone: it needs no language and does no analysis
if (( CLEAN_ONLY )); then
    (( ${#positional_arguments} == 0 )) ||
        fail_setup "--clean takes no language argument"
    clean_artifacts
    exit 0
fi

if (( ${#positional_arguments} == 0 )); then
    print_colored "${COLOR_RED}" "No language given"
    usage
    exit 2
fi

(( ${#positional_arguments} == 1 )) ||
    fail_setup "Expected one language, got: ${positional_arguments[*]}"

case "${requested_format}" in
    sarif|sarif-latest)
        OUTPUT_FORMAT="sarif-latest"
        OUTPUT_EXTENSION="sarif"
        ;;
    csv)
        OUTPUT_FORMAT="csv"
        OUTPUT_EXTENSION="csv"
        ;;
    *)
        fail_setup "Unsupported format: ${requested_format}. Use sarif or csv."
        ;;
esac

[[ "${THREAD_COUNT}" == <-> || "${THREAD_COUNT}" == -<-> ]] ||
    fail_setup "--threads expects an integer, got: ${THREAD_COUNT}"

if [[ -n "${BUILD_MODE}" ]]; then
    case "${BUILD_MODE}" in
        none|autobuild|manual) ;;
        *) fail_setup "Unsupported build mode: ${BUILD_MODE}. Use none, autobuild, or manual." ;;
    esac
fi

[[ -d "${CODEQL_REPO}" ]] ||
    fail_setup "CodeQL query checkout not found: ${CODEQL_REPO}. Clone github/codeql or set CODEQL_REPO."

language="$(resolve_language "${positional_arguments[1]}")"

[[ -d "${CODEQL_REPO}/${language}" ]] ||
    fail_setup "No '${language}' queries in ${CODEQL_REPO}"

require_commands

# Resolve and validate every requested suite before running anything, so a typo
# fails immediately rather than after a long database build.
typeset -a selected_suites=()
if [[ "${SUITE_SELECTION}" == "all" || "${SUITE_SELECTION}" == "both" ]]; then
    selected_suites=(security-extended security-and-quality)
else
    for requested_suite in ${(s:,:)SUITE_SELECTION}; do
        [[ -n "${requested_suite}" ]] || continue
        selected_suites+=("$(resolve_suite_name "${requested_suite}")")
    done
fi

(( ${#selected_suites} > 0 )) || fail_setup "No suites selected by --suite ${SUITE_SELECTION}"

typeset -a selected_suite_specs=()
for suite in "${selected_suites[@]}"; do
    suite_path="$(suite_path_for "${language}" "${suite}")"
    [[ -f "${suite_path}" ]] ||
        fail_setup "Query suite not found: ${suite_path}"
    selected_suite_specs+=("$(suite_spec_for "${language}" "${suite}")")
done

if (( ! CREATE_DATABASE )) && [[ ! -d "${DATABASE_PATH}" ]]; then
    fail_setup "Database '${DATABASE_PATH}' not found, and --no-create was given. Drop --no-create to build it."
fi

print_colored "${COLOR_BRIGHTYELLOW}" "Language: ${language}   Format: ${OUTPUT_FORMAT}   Suites: ${selected_suites[*]}"
if (( DRY_RUN )); then
    print_colored "${COLOR_BRIGHTYELLOW}" "Dry run: showing commands only"
fi

if (( CREATE_DATABASE )); then
    create_database "${language}"
else
    print_colored "${COLOR_BRIGHTYELLOW}" "Reusing existing database '${DATABASE_PATH}'"
fi

if (( ! DRY_RUN )); then
    mkdir -p "${OUTPUT_DIRECTORY}"
fi

# Run every suite even if one fails, then report which ones did
typeset -a failed_suites=()
suite_index=1
for suite in "${selected_suites[@]}"; do
    analyze_suite "${suite}" "${selected_suite_specs[${suite_index}]}" ||
        failed_suites+=("${suite}")
    (( suite_index += 1 ))
done

print_colored "${COLOR_BRIGHTYELLOW}" ""
print_colored "${COLOR_BRIGHTYELLOW}" "Summary:"
print_colored "${COLOR_BRIGHTYELLOW}" "-----------"
for suite in "${selected_suites[@]}"; do
    if (( ${failed_suites[(Ie)${suite}]} )); then
        print_colored "${COLOR_RED}" "${suite}: FAILED"
    elif (( DRY_RUN )); then
        print_colored "${COLOR_CYAN}" "${suite}: not run (dry run)"
    else
        print_colored "${COLOR_GREEN}" "${suite}: ${OUTPUT_DIRECTORY}/codeqlAnalysis_${suite}.${OUTPUT_EXTENSION}"
    fi
done

if (( ${#failed_suites} > 0 )); then
    exit 1
fi
