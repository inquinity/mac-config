#!/usr/bin/env bash
# Report whether a GitHub repository requires signed commits on its default branch:
# the repository in the current directory by default, or whole owners with --all.
# Read-only: makes GitHub API calls through the gh CLI, changes nothing.
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

# Owners (users or organizations) to check when --all is given without any owner
DEFAULT_OWNERS=(inquinity Open-Lens)

required_count=0
missing_count=0
unknown_count=0

usage() {
    print_colored "$COLOR_YELLOW" "Usage: ${0##*/} [-h|--help] [--all] [owner ...]"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Reports whether signed commits are required on the default branch by a"
    print_colored "$COLOR_YELLOW" "repository or organization ruleset."
    print_colored "$COLOR_YELLOW" "  (no arguments)  check the repository in the current directory"
    print_colored "$COLOR_YELLOW" "  --all           check every non-archived repository of the default owners:"
    print_colored "$COLOR_YELLOW" "                  ${DEFAULT_OWNERS[*]}"
    print_colored "$COLOR_YELLOW" "  owner ...       check every non-archived repository of these owners instead"
    print_colored "$COLOR_YELLOW" "                  (--all is ignored when owners are given)"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Status: REQUIRED, NOT REQUIRED, or UNKNOWN (the ruleset check failed, for"
    print_colored "$COLOR_YELLOW" "example missing permission to read rules, or an API error)."
    print_colored "$COLOR_YELLOW" "Exit status: 0 if all repositories require signing, 1 if any do not or are"
    print_colored "$COLOR_YELLOW" "unknown, 2 on usage or setup errors."
}

require_commands() {
    local command_name
    for command_name in gh jq; do
        command -v "$command_name" >/dev/null 2>&1 || {
            print_colored "$COLOR_RED" "Required command not found: ${command_name}"
            exit 2
        }
    done
    gh auth status >/dev/null 2>&1 || {
        print_colored "$COLOR_RED" "gh is not authenticated; run: gh auth login"
        exit 2
    }
}

# Query one API path and print the --jq result.
# Returns 0 on success, 1 on HTTP 404 (nothing configured), 2 on any other failure.
api_value() {
    local api_path=$1
    local jq_filter=$2
    local output
    if output=$(gh api "$api_path" --jq "$jq_filter" 2>&1); then
        printf '%s' "$output"
        return 0
    fi
    [[ "$output" == *"HTTP 404"* ]] && return 1
    return 2
}

# Print yes, no, or unknown for one check, given the api_value result.
# Arguments: api_path jq_filter
check_to_word() {
    local value
    local result_code=0
    value=$(api_value "$1" "$2") || result_code=$?
    case "$result_code" in
        0) [[ "$value" == "true" ]] && printf 'yes' || printf 'no' ;;
        1) printf 'no' ;;
        *) printf 'unknown' ;;
    esac
}

check_repo() {
    local repo=$1
    local branch=$2
    local ruleset_state status color row

    # Rulesets: the rules that currently apply to this branch
    ruleset_state=$(check_to_word "repos/${repo}/rules/branches/${branch}" \
        'any(.[]; .type == "required_signatures")')

    case "$ruleset_state" in
        yes) status="REQUIRED";     color=$COLOR_GREEN;        required_count=$((required_count + 1)) ;;
        no)  status="NOT REQUIRED"; color=$COLOR_RED;          missing_count=$((missing_count + 1)) ;;
        *)   status="UNKNOWN";      color=$COLOR_BRIGHTYELLOW; unknown_count=$((unknown_count + 1)) ;;
    esac

    printf -v row '%-45s %-12s %s' \
        "$repo" "$branch" "$status"
    print_colored "$color" "$row"
}

check_owner() {
    local owner=$1
    local repo_list repo branch

    print_colored "$COLOR_CYAN" "== ${owner}"
    if ! repo_list=$(gh repo list "$owner" --limit 1000 --no-archived \
        --json nameWithOwner,defaultBranchRef \
        --jq '.[] | [.nameWithOwner, (.defaultBranchRef.name // "")] | @tsv' 2>&1); then
        print_colored "$COLOR_RED" "Could not list repositories for ${owner}: ${repo_list}"
        unknown_count=$((unknown_count + 1))
        return 0
    fi

    while IFS=$'\t' read -r repo branch; do
        [[ -n "$repo" ]] || continue
        if [[ -z "$branch" ]]; then
            print_colored "$COLOR_YELLOW" "$(printf '%-45s (empty repository, skipped)' "$repo")"
            continue
        fi
        check_repo "$repo" "$branch"
    done <<<"$repo_list"
}

# Check only the repository in the current directory, resolved through its GitHub remote.
check_current_repo() {
    local repo_info repo branch

    if ! repo_info=$(gh repo view --json nameWithOwner,defaultBranchRef \
        --jq '[.nameWithOwner, (.defaultBranchRef.name // "")] | @tsv' 2>&1); then
        print_colored "$COLOR_RED" "Could not resolve a GitHub repository here: ${repo_info}"
        print_colored "$COLOR_YELLOW" "Run this inside a clone with a GitHub remote, or name owners, or use --all."
        exit 2
    fi

    IFS=$'\t' read -r repo branch <<<"$repo_info"
    [[ -n "$repo" ]] || {
        print_colored "$COLOR_RED" "Could not determine the repository for the current directory"
        exit 2
    }

    print_colored "$COLOR_CYAN" "== ${repo}"
    if [[ -z "$branch" ]]; then
        print_colored "$COLOR_YELLOW" "$(printf '%-45s (empty repository, skipped)' "$repo")"
        return 0
    fi
    check_repo "$repo" "$branch"
}

main() {
    local owners=()
    local check_all=false
    local argument
    for argument in "$@"; do
        case "$argument" in
            -h|--help) usage; exit 0 ;;
            --all) check_all=true ;;
            -*) print_colored "$COLOR_RED" "Unknown option: ${argument}"; usage; exit 2 ;;
            *) owners+=("$argument") ;;
        esac
    done

    require_commands

    if [[ ${#owners[@]} -eq 0 && "$check_all" != true ]]; then
        check_current_repo
    else
        [[ ${#owners[@]} -gt 0 ]] || owners=("${DEFAULT_OWNERS[@]}")
        local owner
        for owner in "${owners[@]}"; do
            check_owner "$owner"
        done
    fi

    printf '\n'
    print_colored "$COLOR_BRIGHTYELLOW" \
        "Required: ${required_count}   Not required: ${missing_count}   Unknown: ${unknown_count}"
    [[ $((missing_count + unknown_count)) -eq 0 ]]
}

main "$@"
