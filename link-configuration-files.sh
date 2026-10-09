#!/usr/bin/env bash
#
# link-configuration-files.sh - Symlink this repo's configuration into $HOME.
#
# Files under zsh/ and git/ that become dotfiles are stored without their
# leading dot so they are visible in ls and Finder. This script is the only
# place the dot is added back: each entry in LINKS maps a repo file to the
# name it has in $HOME.
#
# Machine-specific git settings (email, commit signing) live in
# git/gitconfig.home and git/gitconfig.work. The shared gitconfig includes
# ~/.gitconfig.local, and this script points that name at the file for this
# computer, based on the profile from zsh/profile.sh (home or work).
#
# ~/.emacs.d is linked to one of the configs under emacs/ (mac-port or
# ns-port). By default the port is detected from the installed Emacs.app;
# --emacs chooses one, or none to remove the link.
#
# ~/.config/eza/theme.yml is linked to eza-themes/default-rda.yml, but only
# when ~/.config/eza already exists -- this script creates dotfile symlinks,
# not the directories that hold them, so a machine without eza configured is
# left alone rather than growing a new, empty ~/.config/eza.
#
# Existing files are never overwritten silently: a real file that differs
# from the repo copy is left alone unless --force is given.

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
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

# Repo file (relative to this script) and the name it takes in $HOME.
LINKS=(
    "git/gitconfig:.gitconfig"
    "git/gitconfig.personal:.gitconfig.personal"
    "git/gitignore_global:.gitignore_global"
    "zsh/zshenv:.zshenv"
    "zsh/zshrc:.zshrc"
    "zsh/zprofile:.zprofile"
    "zsh/zlogin:.zlogin"
)

LOCAL_LINK_NAME=".gitconfig.local"
EMACS_LINK_NAME=".emacs.d"
EMACS_PORTS=(mac-port ns-port)
EZA_THEME_SOURCE="eza-themes/default-rda.yml"
EZA_THEME_LINK_NAME=".config/eza/theme.yml"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_emacs_dir="$script_dir/emacs"
# shellcheck source=zsh/profile.sh
source "$script_dir/zsh/profile.sh"
dry_run=false
force=false
profile=""          # home | work; detected from the hostname unless given
emacs_mode=auto     # auto | mac-port | ns-port | none
problem_count=0

usage() {
    print_colored "$COLOR_YELLOW" "link-configuration-files.sh - symlink this repo's configuration into \$HOME"
    cat <<'USAGE'

Usage:
  link-configuration-files.sh [options]

Options:
  -n, --dry-run        Show what would change without changing anything
  -f, --force          Replace existing files that differ from the repo copy
      --profile NAME   Use home or work instead of detecting from hostname
      --emacs MODE     Link ~/.emacs.d to mac-port or ns-port, or none to
                       remove the link (default: auto, detect from Emacs.app)
  -h, --help           Show this help
USAGE
}

# Emacs.app bundles on this computer. Spotlight finds them wherever they are
# installed (no package manager is assumed); the fixed paths cover computers
# with Spotlight indexing turned off.
find_emacs_apps() {
    local app_path
    {
        mdfind "kMDItemCFBundleIdentifier == 'org.gnu.Emacs'" 2>/dev/null || true
        printf '%s\n' /Applications/Emacs.app "$HOME/Applications/Emacs.app"
    } | while IFS= read -r app_path; do
        # Skip copies in the Trash and on mounted volumes (installer DMGs, backups).
        if [[ -d "$app_path/Contents/MacOS" && "$app_path" != */.Trash/* && "$app_path" != /Volumes/* ]]; then
            printf '%s\n' "$app_path"
        fi
    done | sort -u
}

# The port an Emacs.app was built as, or nothing if unknown. Emacs embeds its
# ./configure options as text in its binaries, so this reads them without
# running the app: --with-mac is the mac port, --with-ns is GNU's NS build.
emacs_app_port() {
    local macos_dir="$1/Contents/MacOS"
    if grep -a -q -s -e '--with-mac' "$macos_dir"/*; then
        printf 'mac-port'
    elif grep -a -q -s -e '--with-ns' "$macos_dir"/*; then
        printf 'ns-port'
    fi
}

# Space-separated list of the distinct ports installed; empty when none.
detect_emacs_ports() {
    local app_path app_port detected_ports=""
    while IFS= read -r app_path; do
        app_port=$(emacs_app_port "$app_path")
        if [[ -n "$app_port" && " $detected_ports " != *" $app_port "* ]]; then
            detected_ports+=" $app_port"
        fi
    done < <(find_emacs_apps)
    printf '%s' "${detected_ports# }"
}

report_problem() {
    print_colored "$COLOR_RED" "  $1"
    problem_count=$((problem_count + 1))
}

# Create or replace one symlink, following the safety rules in the header.
link_one() {
    local source_path=$1
    local link_path=$2
    local reason=""

    if [[ ! -e "$source_path" ]]; then
        report_problem "missing repo file: $source_path"
        return 0
    fi

    if [[ -L "$link_path" ]]; then
        # -ef compares the files the paths resolve to, so a relative link or a
        # different spelling of the same path (symlinked $HOME or repo) is fine.
        if [[ "$link_path" -ef "$source_path" ]]; then
            print_colored "$COLOR_GREEN" "  ok        $link_path"
            return 0
        fi
        reason="points elsewhere: $(readlink "$link_path")"
    elif [[ -d "$link_path" ]]; then
        reason="existing directory"
    elif [[ -e "$link_path" ]]; then
        if cmp -s "$source_path" "$link_path"; then
            reason="identical copy"
        else
            reason="differs from repo"
        fi
    fi

    # Anything that already exists and is not just an identical copy needs --force.
    if [[ -n "$reason" && "$reason" != "identical copy" && "$force" == false ]]; then
        report_problem "$link_path $reason; not replaced (re-run with --force after checking it)"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  would link ${link_path} -> ${source_path}${reason:+ ($reason)}"
        return 0
    fi

    # ln -sfn cannot replace a real directory (it would create the link inside
    # it), so remove the directory first; reaching here required --force.
    if [[ -d "$link_path" && ! -L "$link_path" ]]; then
        rm -rf -- "$link_path"
    fi
    ln -sfn "$source_path" "$link_path"
    print_colored "$COLOR_BRIGHTYELLOW" "  linked    ${link_path} -> ${source_path}${reason:+ ($reason)}"
}

# Remove the ~/.emacs.d link, but only when it points at one of this repo's
# configs; a real directory or a link to anything else is not ours to delete.
unlink_emacs_config() {
    local link_path=$1
    local port

    if [[ ! -L "$link_path" ]]; then
        if [[ -e "$link_path" ]]; then
            print_colored "$COLOR_YELLOW" "  left      $link_path (not a link; not removed)"
        else
            print_colored "$COLOR_GREEN" "  ok        $link_path (no link)"
        fi
        return 0
    fi

    for port in "${EMACS_PORTS[@]}"; do
        if [[ "$link_path" -ef "$repo_emacs_dir/$port" ]]; then
            if [[ "$dry_run" == true ]]; then
                print_colored "$COLOR_BRIGHTYELLOW" "  would remove ${link_path} -> $(readlink "$link_path")"
            else
                rm -- "$link_path"
                print_colored "$COLOR_BRIGHTYELLOW" "  removed   ${link_path}"
            fi
            return 0
        fi
    done
    print_colored "$COLOR_YELLOW" "  left      $link_path (links elsewhere: $(readlink "$link_path"))"
}

# Link, unlink, or skip ~/.emacs.d according to emacs_mode.
link_emacs_config() {
    local link_path="$HOME/$EMACS_LINK_NAME"
    local emacs_port=$emacs_mode

    if [[ "$emacs_port" == auto ]]; then
        emacs_port=$(detect_emacs_ports)
        case $emacs_port in
            "")
                print_colored "$COLOR_YELLOW" "Emacs: no Emacs.app with a recognized port found; ~/.emacs.d not changed (choose with --emacs)"
                return 0
                ;;
            *" "*)
                print_colored "$COLOR_YELLOW" "Emacs: found more than one port ($emacs_port); ~/.emacs.d not changed (choose with --emacs)"
                return 0
                ;;
        esac
        print_colored "$COLOR_YELLOW" "Emacs: $emacs_port (detected)"
    else
        print_colored "$COLOR_YELLOW" "Emacs: $emacs_port"
    fi

    if [[ "$emacs_port" == none ]]; then
        unlink_emacs_config "$link_path"
    else
        link_one "$repo_emacs_dir/$emacs_port" "$link_path"
    fi
}

# Link ~/.config/eza/theme.yml, but only when ~/.config/eza already exists.
# This script creates dotfile symlinks, not the directories that hold them --
# a machine without eza configured should stay that way, not grow a new,
# empty ~/.config/eza just because this script ran.
link_eza_theme() {
    local config_dir="$HOME/.config/eza"

    if [[ -d "$config_dir" ]]; then
	print_colored "$COLOR_YELLOW" "eza theme:"
    else
        print_colored "$COLOR_YELLOW" "eza theme: ~/.config/eza not found; theme not linked"
        return 0
    fi
    link_one "$script_dir/$EZA_THEME_SOURCE" "$HOME/$EZA_THEME_LINK_NAME"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run) dry_run=true ;;
        -f|--force) force=true ;;
        --profile)
            [[ $# -ge 2 ]] || { print_colored "$COLOR_RED" "--profile needs a value"; exit 2; }
            profile=$2
            shift
            ;;
        --emacs)
            [[ $# -ge 2 ]] || { print_colored "$COLOR_RED" "--emacs needs a value"; exit 2; }
            emacs_mode=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

if [[ -z "$profile" ]]; then
    profile=$(current_profile)
fi
case $profile in
    home|work) ;;
    *) print_colored "$COLOR_RED" "Unknown profile '$profile' (expected home or work)"; exit 2 ;;
esac
case $emacs_mode in
    auto|mac-port|ns-port|none) ;;
    *) print_colored "$COLOR_RED" "Unknown --emacs mode '$emacs_mode' (expected auto, mac-port, ns-port, or none)"; exit 2 ;;
esac

print_colored "$COLOR_YELLOW" "Profile: $profile ($(computer_name))"
[[ "$dry_run" == true ]] && print_colored "$COLOR_YELLOW" "Dry run: no changes will be made"

for link_entry in "${LINKS[@]}"; do
    link_one "$script_dir/${link_entry%%:*}" "$HOME/${link_entry#*:}"
done
link_one "$script_dir/git/gitconfig.$profile" "$HOME/$LOCAL_LINK_NAME"
link_emacs_config
link_eza_theme

if [[ $problem_count -gt 0 ]]; then
    print_colored "$COLOR_RED" "$problem_count problem(s); see above"
    exit 1
fi
print_colored "$COLOR_GREEN" "Done"
