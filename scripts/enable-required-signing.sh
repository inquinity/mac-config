#!/usr/bin/env bash
# Create GitHub rulesets that require signed commits on a repository's default branch
# and signed tags matching v*. Dry run by default; pass --apply to create them.
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

BRANCH_RULESET_NAME="Require signed commits"
TAG_RULESET_NAME="Require signed tags"
TAG_PATTERN="refs/tags/v*"

apply_changes=false

usage() {
    print_colored "$COLOR_YELLOW" "Usage: ${0##*/} [-n|--dry-run] [--apply] [-h|--help] owner/repo [owner/repo ...]"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Creates two rulesets per repository, with no bypass actors:"
    print_colored "$COLOR_YELLOW" "  \"${BRANCH_RULESET_NAME}\"  default branch must have signed commits"
    print_colored "$COLOR_YELLOW" "  \"${TAG_RULESET_NAME}\"     tags matching ${TAG_PATTERN#refs/tags/} must be signed"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Default is a dry run: only reads from GitHub and prints what would be created."
    print_colored "$COLOR_YELLOW" "  --apply    create the rulesets (changes the live repositories)"
    print_colored "$COLOR_YELLOW" "Rulesets that already exist by name are skipped, so reruns are safe."
    print_colored "$COLOR_YELLOW" "To undo: delete the ruleset under the repository's Settings > Rules."
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

# Build the JSON body for one ruleset.
# Arguments: name target (branch|tag) ref_include
build_ruleset_payload() {
    jq -n --arg name "$1" --arg target "$2" --arg ref_include "$3" '{
        name: $name,
        target: $target,
        enforcement: "active",
        bypass_actors: [],
        conditions: { ref_name: { include: [$ref_include], exclude: [] } },
        rules: [ { type: "required_signatures" } ]
    }'
}

# Create one ruleset on a repository unless one with that name already exists.
# Arguments: repo existing_names ruleset_name target ref_include
ensure_ruleset() {
    local repo=$1
    local existing_names=$2
    local ruleset_name=$3
    local target=$4
    local ref_include=$5
    local payload

    if grep -Fxq -- "$ruleset_name" <<<"$existing_names"; then
        print_colored "$COLOR_YELLOW" "  exists, skipped: ${ruleset_name}"
        return 0
    fi

    payload=$(build_ruleset_payload "$ruleset_name" "$target" "$ref_include")
    if [[ "$apply_changes" == true ]]; then
        gh api --method POST "repos/${repo}/rulesets" --input - <<<"$payload" >/dev/null
        print_colored "$COLOR_GREEN" "  created: ${ruleset_name} (${target}, ${ref_include})"
    else
        print_colored "$COLOR_BRIGHTYELLOW" "  would create: ${ruleset_name} (${target}, ${ref_include})"
        jq -c . <<<"$payload" | sed 's/^/      /'
    fi
}

process_repo() {
    local repo=$1
    local repo_info default_branch is_fork can_admin existing_names

    print_colored "$COLOR_CYAN" "== ${repo}"
    if ! repo_info=$(gh api "repos/${repo}" \
        --jq '[.default_branch, .fork, .permissions.admin] | @tsv' 2>&1); then
        print_colored "$COLOR_RED" "  cannot read repository: ${repo_info}"
        return 1
    fi
    IFS=$'\t' read -r default_branch is_fork can_admin <<<"$repo_info"

    if [[ "$is_fork" == "true" ]]; then
        print_colored "$COLOR_RED" "  is a fork; skipped (upstream syncs bring unsigned commits)"
        return 1
    fi
    if [[ "$can_admin" != "true" ]]; then
        print_colored "$COLOR_RED" "  no admin permission; cannot manage rulesets"
        return 1
    fi

    existing_names=$(gh api "repos/${repo}/rulesets" --jq '.[].name')
    print_colored "$COLOR_YELLOW" "  default branch: ${default_branch}"

    ensure_ruleset "$repo" "$existing_names" "$BRANCH_RULESET_NAME" branch "~DEFAULT_BRANCH"
    ensure_ruleset "$repo" "$existing_names" "$TAG_RULESET_NAME" tag "$TAG_PATTERN"
}

main() {
    local repos=()
    local argument
    for argument in "$@"; do
        case "$argument" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) apply_changes=false ;;
            --apply) apply_changes=true ;;
            -*) print_colored "$COLOR_RED" "Unknown option: ${argument}"; usage; exit 2 ;;
            */*) repos+=("$argument") ;;
            *) print_colored "$COLOR_RED" "Expected owner/repo, got: ${argument}"; exit 2 ;;
        esac
    done
    if [[ ${#repos[@]} -eq 0 ]]; then
        print_colored "$COLOR_RED" "No repositories given."
        usage
        exit 2
    fi

    require_commands

    if [[ "$apply_changes" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "APPLY: creating rulesets on live repositories"
    else
        print_colored "$COLOR_BRIGHTYELLOW" "DRY RUN: nothing will be created (use --apply to create)"
    fi

    local repo
    local failures=0
    for repo in "${repos[@]}"; do
        process_repo "$repo" || failures=$((failures + 1))
    done

    [[ "$failures" -eq 0 ]]
}

main "$@"
