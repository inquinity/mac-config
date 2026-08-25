#!/bin/bash

# brew-safe.sh
# Version: 1.0
# Author: robert.altman@optum.com
# Description: Runs a brew command against a homebrew/core tap pinned to a commit
#              from N days ago, giving new formula releases a cool-off period
#              before they can be installed. This is the Homebrew counterpart to
#              PIP_UPLOADED_PRIOR_TO / POETRY_SOLVER_MIN_RELEASE_AGE /
#              UV_EXCLUDE_NEWER, which apply the same idea to Python tooling.
#
#              The tap is always restored to its original ref, including on
#              failure or Ctrl-C, via an EXIT trap.
#
# Origin: started life as a brew-safe() function in ~/.zshrc. It was never
#         actually run, and would not have worked: it restored the tap with
#         "git checkout master", but homebrew/core's branch is "main", so every
#         invocation would have left the tap detached at an old commit with the
#         error hidden by 2>/dev/null. Kept here in reserve rather than adopted.

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

usage() {
    printf "${COLOR_YELLOW}Run a brew command against a time-pinned homebrew/core${COLOR_RESET}\n"
    printf "Usage: %s [--days N] [--dry-run|-n] [--debug] [--help|-h] -- BREW_ARGS...\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  --days N        Cool-off period in days (default: %s)\n" "$DEFAULT_DAYS"
    printf "  --dry-run, -n   Show actions without checking out or running brew\n"
    printf "  --debug         Show additional diagnostic output\n"
    printf "  --help, -h      Show this help message\n"
    printf "\n"
    printf "${COLOR_YELLOW}Examples:${COLOR_RESET}\n"
    printf "  %s install jq              # install jq as it existed %s days ago\n" "$(basename "$0")" "$DEFAULT_DAYS"
    printf "  %s --days 14 upgrade jq    # use a 14-day cool-off\n" "$(basename "$0")"
    printf "  %s -n install jq           # show what would happen\n" "$(basename "$0")"
    printf "\n"
    printf "The first non-option argument and everything after it is passed to brew.\n"
    printf "Use -- if a brew argument would otherwise look like an option.\n"
}

DEFAULT_DAYS=6
days="$DEFAULT_DAYS"
dry_run=0
debug=0
brew_args=()

# Parse our own options up to the first non-option argument (or --); everything
# from there on belongs to brew.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --days)
            if [[ $# -lt 2 ]]; then
                print_colored "$COLOR_RED" "Error: --days requires a value."
                exit 2
            fi
            days=$2
            shift 2
            ;;
        --dry-run|-n)
            dry_run=1
            shift
            ;;
        --debug)
            debug=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            brew_args=("$@")
            break
            ;;
        *)
            brew_args=("$@")
            break
            ;;
    esac
done

debug_print() {
    [[ "$debug" -eq 1 ]] && print_colored "$COLOR_CYAN" "  [debug] $1"
    return 0
}

# --- Validation -------------------------------------------------------------

if [[ "$(uname)" != "Darwin" ]]; then
    print_colored "$COLOR_RED" "This script only supports macOS."
    exit 1
fi

if [[ ! "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
    print_colored "$COLOR_RED" "Error: --days must be a positive integer (got: $days)."
    exit 2
fi

if [[ ${#brew_args[@]} -eq 0 ]]; then
    print_colored "$COLOR_RED" "Error: no brew command given."
    printf "\n"
    usage
    exit 2
fi

if ! command -v brew >/dev/null 2>&1; then
    print_colored "$COLOR_RED" "Error: brew not found on PATH."
    exit 1
fi

core_repo="$(brew --repo homebrew/core 2>/dev/null || true)"
if [[ -z "$core_repo" || ! -d "$core_repo/.git" ]]; then
    print_colored "$COLOR_RED" "Error: homebrew/core is not tapped as a git repository."
    print_colored "$COLOR_YELLOW" "Pinning by commit needs the tap checked out. Run: brew tap --force homebrew/core"
    exit 1
fi
debug_print "core repo: $core_repo"

# A dirty tap means a checkout could fail partway or discard local edits.
if [[ -n "$(git -C "$core_repo" status --porcelain 2>/dev/null)" ]]; then
    print_colored "$COLOR_RED" "Error: homebrew/core has uncommitted changes."
    print_colored "$COLOR_YELLOW" "Resolve them first: git -C \"$core_repo\" status"
    exit 1
fi

# Record exactly where to return to. A branch name when HEAD is on one,
# otherwise the raw commit -- so a tap left detached by something else is
# still restored to where we found it rather than to an assumed branch.
if original_ref="$(git -C "$core_repo" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    debug_print "original ref: branch $original_ref"
else
    original_ref="$(git -C "$core_repo" rev-parse HEAD)"
    print_colored "$COLOR_YELLOW" "Warning: homebrew/core is already detached at ${original_ref:0:12}."
    print_colored "$COLOR_YELLOW" "It will be restored to that same commit, not to a branch."
fi

old_commit="$(git -C "$core_repo" log --before="${days} days ago" -1 --format='%H' "$original_ref" 2>/dev/null || true)"
if [[ -z "$old_commit" ]]; then
    print_colored "$COLOR_RED" "Error: no homebrew/core commit found older than ${days} days."
    print_colored "$COLOR_YELLOW" "The tap may be a shallow clone. Try: git -C \"$core_repo\" fetch --unshallow"
    exit 1
fi

old_commit_date="$(git -C "$core_repo" log -1 --format='%ci' "$old_commit")"
print_colored "$COLOR_BRIGHTYELLOW" "Pinning homebrew/core to ${old_commit:0:12} (${old_commit_date}), a ${days}-day cool-off."

if [[ "$dry_run" -eq 1 ]]; then
    printf "[dry-run] git -C %s checkout --quiet --detach %s\n" "$core_repo" "$old_commit"
    printf "[dry-run] brew %s\n" "${brew_args[*]}"
    printf "[dry-run] git -C %s checkout --quiet %s\n" "$core_repo" "$original_ref"
    print_colored "$COLOR_GREEN" "Dry run complete. Nothing was changed."
    exit 0
fi

# --- Pin, run, always restore ----------------------------------------------

checked_out=0

restore_ref() {
    local rc=$?
    if [[ "$checked_out" -eq 1 ]]; then
        printf "\n"
        if git -C "$core_repo" checkout --quiet "$original_ref" 2>/dev/null; then
            print_colored "$COLOR_GREEN" "Restored homebrew/core to ${original_ref}."
        else
            # Leaving the tap detached silently is what made the original
            # version dangerous, so make the recovery step loud and explicit.
            print_colored "$COLOR_RED" "FAILED to restore homebrew/core -- it is still detached."
            print_colored "$COLOR_RED" "Recover with: git -C \"$core_repo\" checkout $original_ref"
        fi
    fi
    return "$rc"
}

# Cleanup runs from the EXIT trap; INT/TERM just exit so that trap fires once.
trap restore_ref EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

git -C "$core_repo" checkout --quiet --detach "$old_commit"
checked_out=1
debug_print "detached at $old_commit"

# HOMEBREW_NO_INSTALL_FROM_API makes brew read the pinned local tap instead of
# the formula API, and HOMEBREW_NO_AUTO_UPDATE stops brew from fetching the tap
# and undoing the pin. Both are set here rather than inherited, so the script
# behaves the same outside an interactive shell.
print_colored "$COLOR_BRIGHTYELLOW" "Running: brew ${brew_args[*]}"
set +e
HOMEBREW_NO_INSTALL_FROM_API=1 HOMEBREW_NO_AUTO_UPDATE=1 brew "${brew_args[@]}"
brew_rc=$?
set -e

if [[ "$brew_rc" -eq 0 ]]; then
    print_colored "$COLOR_GREEN" "brew ${brew_args[*]} succeeded."
else
    print_colored "$COLOR_RED" "brew ${brew_args[*]} exited with status ${brew_rc}."
fi

exit "$brew_rc"
