#!/usr/bin/env bash
# Keep the git signing key's passphrase in the macOS keychain so signing never prompts.
#
# This is per user, not per repository. Git signs with `ssh-keygen -Y sign`, which asks
# ssh-agent for the key and never reads the keychain itself. So two things are needed:
#   1. the passphrase stored in the login keychain (ssh-add --apple-use-keychain), and
#   2. the keys in the keychain loaded into ssh-agent at every login
#      (ssh-add --apple-load-keychain), which this script adds to zsh/zprofile.
# After storing, the script removes the key from the agent and reloads it from the keychain
# to prove the round trip works. It uses /usr/bin/ssh-add because a Homebrew OpenSSH
# earlier in PATH lacks the Apple keychain options and talks to a different agent.
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

SYSTEM_SSH_ADD="/usr/bin/ssh-add"
LOGIN_HOOK_MARKER="--apple-load-keychain"

dry_run=false
problem_count=0
key_file=""
zprofile_file=""
key_blob=""

usage() {
    print_colored "$COLOR_YELLOW" "Usage: ${0##*/} [-n|--dry-run] [-h|--help] [--key FILE] [--zprofile FILE]"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Stores the signing key's passphrase in the macOS keychain and makes zsh load it"
    print_colored "$COLOR_YELLOW" "into ssh-agent at login. Run it in a terminal: it may ask for the passphrase once."
    print_colored "$COLOR_YELLOW" "  -n, --dry-run     report and show what would change; do not modify anything"
    print_colored "$COLOR_YELLOW" "  --key FILE        private key (default: git user.signingkey without .pub,"
    print_colored "$COLOR_YELLOW" "                    else ~/.ssh/git-signing)"
    print_colored "$COLOR_YELLOW" "  --zprofile FILE   file that gets the login step (default: zsh/zprofile in this repo)"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Note: with the passphrase in the keychain, any process running as you can sign"
    print_colored "$COLOR_YELLOW" "without a prompt. The passphrase then only protects a copy of the key file."
    print_colored "$COLOR_YELLOW" "Exit status: 0 if ready, 1 if any problem was found, 2 on usage errors."
}

die() {
    print_colored "$COLOR_RED" "$1"
    exit 2
}

note_problem() {
    print_colored "$COLOR_RED" "  problem: $1"
    problem_count=$((problem_count + 1))
}

agent_has_key() {
    "$SYSTEM_SSH_ADD" -L 2>/dev/null | grep -Fq -- "$key_blob"
}

# Drop the key from the agent, reload everything stored in the keychain, and report
# whether the key came back (which proves the passphrase is stored and usable).
reload_from_keychain() {
    "$SYSTEM_SSH_ADD" -d "${key_file}.pub" >/dev/null 2>&1 || true
    "$SYSTEM_SSH_ADD" --apple-load-keychain >/dev/null 2>&1 || true
    agent_has_key
}

key_has_passphrase() {
    # With an empty passphrase this succeeds only if the key is unencrypted
    ! ssh-keygen -y -P "" -f "$key_file" >/dev/null 2>&1
}

store_passphrase() {
    if ! key_has_passphrase; then
        print_colored "$COLOR_YELLOW" "  key has no passphrase; nothing to store in the keychain"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  would check whether the keychain already reloads the key"
        print_colored "$COLOR_BRIGHTYELLOW" "  would run if not: ${SYSTEM_SSH_ADD} --apple-use-keychain ${key_file}"
        return 0
    fi

    if reload_from_keychain; then
        print_colored "$COLOR_GREEN" "  passphrase already in the keychain; key reloads into ssh-agent"
        return 0
    fi

    [[ -t 0 ]] || die "Storing the passphrase needs a terminal; run this script interactively."
    print_colored "$COLOR_YELLOW" "  storing the passphrase in the keychain (enter it when asked)"
    "$SYSTEM_SSH_ADD" --apple-use-keychain "$key_file" || {
        note_problem "ssh-add could not store the key; was the passphrase correct?"
        return 0
    }
    if reload_from_keychain; then
        print_colored "$COLOR_GREEN" "  passphrase stored; key reloads into ssh-agent from the keychain"
    else
        note_problem "the key did not reload from the keychain after storing"
    fi
}

ensure_login_hook() {
    if [[ -f "$zprofile_file" ]] && grep -Fq -- "$LOGIN_HOOK_MARKER" "$zprofile_file"; then
        print_colored "$COLOR_GREEN" "  login step already in ${zprofile_file}"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  would append the login step to ${zprofile_file}"
        return 0
    fi

    [[ -f "$zprofile_file" ]] || {
        note_problem "${zprofile_file} not found"
        return 0
    }
    {
        printf '\n# Load SSH keys whose passphrases are in the keychain (git commit signing).\n'
        printf '# Added by git/configure-keychain-signing.sh; quiet and safe to run repeatedly.\n'
        printf '%s %s >/dev/null 2>&1\n' "$SYSTEM_SSH_ADD" "$LOGIN_HOOK_MARKER"
    } >>"$zprofile_file"
    print_colored "$COLOR_GREEN" "  added the login step to ${zprofile_file}"
    print_colored "$COLOR_YELLOW" "  review and commit that change if it is a tracked dotfile"
}

main() {
    local repo_root argument
    repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

    while [[ $# -gt 0 ]]; do
        argument=$1
        case "$argument" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) dry_run=true ;;
            --key) shift; [[ $# -gt 0 ]] || die "--key needs a file"; key_file=$1 ;;
            --zprofile) shift; [[ $# -gt 0 ]] || die "--zprofile needs a file"; zprofile_file=$1 ;;
            *) print_colored "$COLOR_RED" "Unknown argument: ${argument}"; usage; exit 2 ;;
        esac
        shift
    done

    [[ "$(uname -s)" == "Darwin" ]] || die "The macOS keychain is required; this is not macOS."
    [[ -x "$SYSTEM_SSH_ADD" ]] || die "Not found: ${SYSTEM_SSH_ADD}"
    command -v ssh-keygen >/dev/null 2>&1 || die "Required command not found: ssh-keygen"

    if [[ -z "$key_file" ]]; then
        key_file=$(git config --type=path --get user.signingkey 2>/dev/null || true)
        key_file=${key_file%.pub}
        [[ -n "$key_file" ]] || key_file="${HOME}/.ssh/git-signing"
    fi
    [[ -n "$zprofile_file" ]] || zprofile_file="${repo_root}/zsh/zprofile"

    [[ -f "$key_file" ]] || die "Private key not found: ${key_file}"
    [[ -f "${key_file}.pub" ]] || die "Public key not found: ${key_file}.pub"
    key_blob=$(awk '{print $2}' "${key_file}.pub")

    print_colored "$COLOR_CYAN" "== keychain signing for ${key_file}"
    [[ "$dry_run" == true ]] && print_colored "$COLOR_BRIGHTYELLOW" "DRY RUN: nothing will be modified"

    if agent_has_key; then
        print_colored "$COLOR_GREEN" "  key is currently loaded in ssh-agent"
    else
        print_colored "$COLOR_YELLOW" "  key is not currently loaded in ssh-agent"
    fi

    store_passphrase
    ensure_login_hook

    printf '\n'
    if [[ "$problem_count" -eq 0 ]]; then
        print_colored "$COLOR_GREEN" "Keychain signing is ready; log out and in once to confirm the key loads at login"
    else
        print_colored "$COLOR_RED" "${problem_count} problem(s) found; keychain signing is not ready"
        return 1
    fi
}

main "$@"
