#!/bin/bash

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
    printf "${COLOR_YELLOW}Reset Homebrew (macOS)${COLOR_RESET}\n"
    printf "Usage: %s [--dry-run|-n] [--help|-h]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  --dry-run, -n   Show actions without performing them\n"
    printf "  --help, -h      Show this help message\n"
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_colored "$COLOR_RED" "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "$(uname)" != "Darwin" ]]; then
    print_colored "$COLOR_RED" "This script only supports macOS."
    exit 1
fi

run_cmd() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "[dry-run] %s\n" "$*"
        return 0
    fi
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

remove_path() {
    local target=$1
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf "[dry-run] rm -rf %s\n" "$target"
        else
            run_cmd rm -rf "$target"
        fi
    else
        printf "Skipping missing path: %s\n" "$target"
    fi
}

print_colored "$COLOR_BRIGHTYELLOW" "Removing Homebrew and related files..."

# Remove brew installations
remove_path "/opt/homebrew"
remove_path "/usr/local/Homebrew"
remove_path "/usr/local/bin/brew"
remove_path "/opt/homebrew/bin/brew"

# Remove related directories (common)
remove_path "/usr/local/Caskroom"
remove_path "/usr/local/Cellar"
remove_path "/opt/homebrew/Caskroom"
remove_path "/opt/homebrew/Cellar"

# Remove caches and config
remove_path "${HOME}/Library/Caches/Homebrew"
remove_path "${HOME}/.cache/Homebrew"
remove_path "${HOME}/.brew"
remove_path "${HOME}/.zprofile"
remove_path "${HOME}/.zshrc"

print_colored "$COLOR_GREEN" "Done."