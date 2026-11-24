#!/bin/bash
#
# remove-brew-intel.sh -- remove every trace of Homebrew from an Intel Mac.
#
# Homebrew 7 no longer supports Intel Macs, and brew.rb on these machines is
# modified and unreliable, so this script never runs `brew`. It removes
# Homebrew's files directly.
#
# Scope: only paths Homebrew owns. /usr/local is shared with other software, so
# whole directories (bin, lib, share, ...) are never removed -- only known
# Homebrew paths, plus symlinks that point into the Cellar or Caskroom.
# Applications that casks copied into /Applications are left in place.

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_CYAN="\e[36m"          # Informational messages
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

usage() {
    printf "${COLOR_YELLOW}Remove Homebrew from an Intel Mac${COLOR_RESET}\n"
    printf "Usage: %s [--dry-run|-n] [--yes|-y] [--help|-h]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  --dry-run, -n   Show actions without performing them\n"
    printf "  --yes, -y       Do not ask for confirmation\n"
    printf "  --help, -h      Show this help message\n"
    printf "\n"
    printf "Never runs brew. Refuses to run on Apple Silicon.\n"
}

DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --yes|-y)     ASSUME_YES=1; shift ;;
        --help|-h)    usage; exit 0 ;;
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

# `uname -m` reports x86_64 for a Rosetta shell on Apple Silicon, so ask the
# hardware instead.
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
    print_colored "$COLOR_RED" "This is an Apple Silicon Mac; refusing to run. Use reset-brew.sh instead."
    exit 1
fi

run_cmd() {
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

# Does this symlink point into a Homebrew-owned location?
points_into_homebrew() {
    local target
    target=$(readlink "$1") || return 1
    case "$target" in
        */Cellar/*|*/Caskroom/*|*/Homebrew/*|../opt/*|*/opt/homebrew/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Remove symlinks in $1 that point into Homebrew. Anything else -- regular
# files, directories, or links to non-Homebrew targets -- is left alone.
remove_homebrew_symlinks() {
    local dir=$1 link
    if [[ ! -d "$dir" ]]; then
        printf "Skipping missing directory: %s\n" "$dir"
        return 0
    fi
    while IFS= read -r -d '' link; do
        points_into_homebrew "$link" || continue
        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf "[dry-run] rm %s (-> %s)\n" "$link" "$(readlink "$link")"
        else
            run_cmd rm "$link"
        fi
    done < <(find "$dir" -maxdepth 1 -type l -print0)
}

# List what is installed under a Cellar or Caskroom by reading the directory
# layout (<root>/<name>/<version>...), since brew itself is never run.
list_installed() {
    local label=$1 root=$2 entry name versions count=0
    [[ -d "$root" ]] || return 0
    local lines=()
    for entry in "$root"/*/; do
        [[ -d "$entry" ]] || continue
        name=$(basename "$entry")
        versions=$(find "$entry" -mindepth 1 -maxdepth 1 -not -name '.*' -exec basename {} \; | sort | paste -sd, - | sed 's/,/, /g')
        lines+=("  ${name}${versions:+ (${versions})}")
        count=$((count + 1))
    done
    print_colored "$COLOR_YELLOW" "${label} in ${root}: ${count}"
    if [[ "$count" -gt 0 ]]; then
        printf "%s\n" "${lines[@]}"
    fi
}

print_colored "$COLOR_CYAN" "Intel Mac detected. Homebrew will be removed manually; brew is not run."

print_colored "$COLOR_BRIGHTYELLOW" "Installed Homebrew packages that will be removed:"
list_installed "Formulae" /usr/local/Cellar
list_installed "Casks" /usr/local/Caskroom
list_installed "Formulae" /opt/homebrew/Cellar
list_installed "Casks" /opt/homebrew/Caskroom
printf "\n"

if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
    print_colored "$COLOR_YELLOW" "This permanently deletes Homebrew, all formulae and casks under it, and its caches."
    printf "Type 'yes' to continue: "
    read -r answer
    if [[ "$answer" != "yes" ]]; then
        print_colored "$COLOR_RED" "Aborted."
        exit 1
    fi
fi

print_colored "$COLOR_BRIGHTYELLOW" "Stopping Homebrew services..."
shopt -s nullglob
for plist in "${HOME}"/Library/LaunchAgents/homebrew.mxcl.*.plist; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "[dry-run] launchctl bootout gui/%s %s\n" "$(id -u)" "$plist"
    else
        launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
    fi
done
for plist in /Library/LaunchDaemons/homebrew.mxcl.*.plist; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "[dry-run] launchctl bootout system %s\n" "$plist"
    else
        run_cmd launchctl bootout system "$plist" >/dev/null 2>&1 || true
    fi
done
shopt -u nullglob

print_colored "$COLOR_BRIGHTYELLOW" "Removing Homebrew service definitions..."
for plist in "${HOME}"/Library/LaunchAgents/homebrew.mxcl.*.plist /Library/LaunchDaemons/homebrew.mxcl.*.plist; do
    [[ -e "$plist" ]] && remove_path "$plist"
done

print_colored "$COLOR_BRIGHTYELLOW" "Removing symlinks that point into Homebrew..."
for shared_dir in /usr/local/bin /usr/local/sbin /usr/local/lib /usr/local/include \
    /usr/local/share /usr/local/etc /usr/local/Frameworks /Applications "${HOME}/Applications"; do
    remove_homebrew_symlinks "$shared_dir"
done

print_colored "$COLOR_BRIGHTYELLOW" "Removing Homebrew directories..."
remove_path "/usr/local/Homebrew"
remove_path "/usr/local/bin/brew"
remove_path "/usr/local/Caskroom"
remove_path "/usr/local/Cellar"
remove_path "/usr/local/opt"
remove_path "/usr/local/var/homebrew"
remove_path "/usr/local/Frameworks"
# A migrated or mismatched install may also have an Apple Silicon prefix.
remove_path "/opt/homebrew"

# Specific known files only, never whole directories, so nothing else in
# /usr/local/etc or /usr/local/share is touched.
print_colored "$COLOR_BRIGHTYELLOW" "Removing Homebrew completion, doc and man files..."
remove_path "/usr/local/etc/bash_completion.d/brew"
remove_path "/usr/local/etc/bash_completion.d/brew-services"
remove_path "/usr/local/share/zsh/site-functions/_brew"
remove_path "/usr/local/share/zsh/site-functions/_brew_services"
remove_path "/usr/local/share/fish/vendor_completions.d/brew.fish"
remove_path "/usr/local/share/doc/homebrew"
remove_path "/usr/local/share/man/man1/brew.1"

print_colored "$COLOR_BRIGHTYELLOW" "Removing Homebrew caches, logs and user config..."
remove_path "${HOME}/Library/Caches/Homebrew"
remove_path "${HOME}/Library/Logs/Homebrew"
remove_path "${HOME}/.cache/Homebrew"
remove_path "${HOME}/.config/homebrew"
remove_path "${HOME}/.homebrew"
remove_path "${HOME}/.brew"

print_colored "$COLOR_GREEN" "Done. Open a new shell so PATH picks up the change."
