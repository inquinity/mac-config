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
    printf "${COLOR_YELLOW}Reset Homebrew (macOS, Apple Silicon + Intel)${COLOR_RESET}\n"
    printf "Usage: %s [--dry-run|-n] [--help|-h]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  --dry-run, -n   Show actions without performing them\n"
    printf "  --help, -h      Show this help message\n"
    printf "\n"
    printf "Handles both Homebrew layouts:\n"
    printf "  Apple Silicon: everything lives under /opt/homebrew, so removing\n"
    printf "                 that one directory is a complete, clean removal.\n"
    printf "  Intel:         Homebrew installs INTO /usr/local, a directory\n"
    printf "                 shared with the rest of the system. This script\n"
    printf "                 only removes paths Homebrew itself owns there\n"
    printf "                 (Cellar, Caskroom, opt, var/homebrew, Frameworks,\n"
    printf "                 the brew repo) plus dangling symlinks left behind\n"
    printf "                 in /usr/local/bin, lib, include, share, sbin, etc\n"
    printf "                 once the Cellar they pointed into is gone. It\n"
    printf "                 never deletes a symlink that still resolves, and\n"
    printf "                 never touches non-symlink files in those shared\n"
    printf "                 directories.\n"
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

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    print_colored "$COLOR_CYAN" "Detected Apple Silicon (arm64) — primary prefix: /opt/homebrew"
else
    print_colored "$COLOR_CYAN" "Detected Intel ($ARCH) — primary prefix: /usr/local"
fi
print_colored "$COLOR_CYAN" "Both prefixes are checked regardless, in case of a mismatched or migrated install."

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

# Remove dangling symlinks under a shared directory (Intel only — Apple
# Silicon's /opt/homebrew is wholly owned by Homebrew, so a plain rm -rf of
# the prefix already handles everything, no sweep needed).
#
# Only removes symlinks whose target no longer exists. Never touches a
# regular file, a directory, or a symlink that still resolves — so
# non-Homebrew content living alongside Homebrew's in these shared
# directories is left alone.
clean_dangling_symlinks() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        printf "Skipping missing directory: %s\n" "$dir"
        return 0
    fi
    local broken_links
    broken_links=$(find "$dir" -maxdepth 1 -type l | while read -r link; do
        [[ -e "$link" ]] || printf "%s\n" "$link"
    done)
    if [[ -z "$broken_links" ]]; then
        printf "No dangling symlinks in %s\n" "$dir"
        return 0
    fi
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf "[dry-run] rm %s (dangling symlink)\n" "$link"
        else
            run_cmd rm "$link"
        fi
    done <<< "$broken_links"
}

print_colored "$COLOR_BRIGHTYELLOW" "Removing Homebrew and related files..."

# --- Apple Silicon layout: one self-contained prefix ---
remove_path "/opt/homebrew"

# --- Intel layout: Homebrew lives inside the shared /usr/local prefix ---
remove_path "/usr/local/Homebrew"
remove_path "/usr/local/bin/brew"
remove_path "/usr/local/Caskroom"
remove_path "/usr/local/Cellar"
remove_path "/usr/local/opt"
remove_path "/usr/local/var/homebrew"
remove_path "/usr/local/Frameworks"

# Homebrew's completion/doc files scattered in shared directories. These are
# specific known filenames, not whole directories, so nothing else in
# /usr/local/etc or /usr/local/share is touched.
remove_path "/usr/local/etc/bash_completion.d/brew"
remove_path "/usr/local/share/zsh/site-functions/_brew"
remove_path "/usr/local/share/doc/homebrew"
remove_path "/usr/local/share/man/man1/brew.1"

print_colored "$COLOR_BRIGHTYELLOW" "Sweeping dangling symlinks left in shared Intel directories..."
for shared_dir in /usr/local/bin /usr/local/sbin /usr/local/lib /usr/local/include /usr/local/share; do
    clean_dangling_symlinks "$shared_dir"
done

# --- Caches and config (both architectures) ---
remove_path "${HOME}/Library/Caches/Homebrew"
remove_path "${HOME}/.cache/Homebrew"
remove_path "${HOME}/.brew"

print_colored "$COLOR_GREEN" "Done."
