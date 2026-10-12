#!/usr/bin/env bash
# Make commit and tag signing effective in one local repository, and verify it works.
#
# Signing settings live in ~/.gitconfig.personal (symlinked from this dotfiles repo).
# Normally git includes it for you (gitconfig.home on home computers, or the remote
# match rules in gitconfig.work). If it is not in effect for this repository, this
# script adds it as a repository-local include (the same thing `git personal` does),
# then checks the signing key, allowed signers, and performs a test signature.
#
# It also loads the signing key into ssh-agent from the macOS Keychain when the agent
# does not already hold it, so that commits do not prompt for the key passphrase.
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

# How the include is written to the repository config (matches the `git personal` alias);
# the tilde is deliberately literal, git expands it when reading the config
# shellcheck disable=SC2088
PERSONAL_CONFIG_REF="~/.gitconfig.personal"
PERSONAL_CONFIG_FILE="${HOME}/.gitconfig.personal"

dry_run=false
problem_count=0
repo_root=""
scratch_dir=""

usage() {
    print_colored "$COLOR_YELLOW" "Usage: ${0##*/} [-n|--dry-run] [-h|--help] [path-to-repo]"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Ensures commit and tag signing are in effect for a local repository (default: the"
    print_colored "$COLOR_YELLOW" "current directory), then verifies the key, allowed signers, and a test signature."
    print_colored "$COLOR_YELLOW" "  -n, --dry-run   report and show what would change; do not modify the repository"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Changes made: a repository-local include of ${PERSONAL_CONFIG_REF}, only if signing"
    print_colored "$COLOR_YELLOW" "is not already in effect; and loading the signing key into ssh-agent from the Keychain."
    print_colored "$COLOR_YELLOW" "To undo: git config --local --unset include.path '${PERSONAL_CONFIG_REF}'"
    print_colored "$COLOR_YELLOW" "         ssh-add -d <key-file>   (the agent is cleared at logout in any case)"
    print_colored "$COLOR_YELLOW" "Exit status: 0 if signing is ready, 1 if any problem was found, 2 on usage errors."
}

cleanup() {
    [[ -n "$scratch_dir" && -d "$scratch_dir" ]] && rm -rf "$scratch_dir"
    return 0
}
trap cleanup EXIT

die() {
    print_colored "$COLOR_RED" "$1"
    exit 2
}

note_problem() {
    print_colored "$COLOR_RED" "  problem: $1"
    problem_count=$((problem_count + 1))
}

# Print one effective setting for the repository, empty if unset.
# Arguments: key [type]   (type: bool or path; default is plain)
effective_setting() {
    local key=$1
    local type_option=${2:-}
    if [[ -n "$type_option" ]]; then
        git -C "$repo_root" config --type="$type_option" --get "$key" 2>/dev/null || true
    else
        git -C "$repo_root" config --get "$key" 2>/dev/null || true
    fi
}

# Like effective_setting, but falls back to the personal config file. Used so a dry run
# can still check the key when the include has not been added yet.
setting_or_personal() {
    local key=$1
    local type_option=${2:-}
    local value
    value=$(effective_setting "$key" "$type_option")
    if [[ -z "$value" && -f "$PERSONAL_CONFIG_FILE" ]]; then
        if [[ -n "$type_option" ]]; then
            value=$(git config --file "$PERSONAL_CONFIG_FILE" --type="$type_option" --get "$key" 2>/dev/null || true)
        else
            value=$(git config --file "$PERSONAL_CONFIG_FILE" --get "$key" 2>/dev/null || true)
        fi
    fi
    printf '%s' "$value"
}

signing_is_effective() {
    [[ "$(effective_setting commit.gpgsign bool)" == "true" ]] &&
        [[ "$(effective_setting tag.gpgsign bool)" == "true" ]] &&
        [[ "$(effective_setting gpg.format)" == "ssh" ]] &&
        [[ -n "$(effective_setting user.signingkey)" ]]
}

local_include_present() {
    git -C "$repo_root" config --local --get-all include.path 2>/dev/null |
        grep -Fxq -- "$PERSONAL_CONFIG_REF"
}

ensure_signing_config() {
    if signing_is_effective; then
        print_colored "$COLOR_GREEN" "  signing settings already in effect"
        return 0
    fi

    print_colored "$COLOR_YELLOW" "  signing is not in effect for this repository"
    [[ -f "$PERSONAL_CONFIG_FILE" ]] || {
        note_problem "${PERSONAL_CONFIG_FILE} is missing; run link-configuration-files.sh from the mac-config repo"
        return 0
    }

    if local_include_present; then
        note_problem "the local include is present but signing is still not effective; inspect ${PERSONAL_CONFIG_FILE}"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  would run: git config --local --add include.path ${PERSONAL_CONFIG_REF}"
        return 0
    fi

    git -C "$repo_root" config --local --add include.path "$PERSONAL_CONFIG_REF"
    print_colored "$COLOR_GREEN" "  added local include of ${PERSONAL_CONFIG_REF}"
    signing_is_effective || note_problem "signing is still not effective after adding the include"
}

# True if ssh-agent currently holds the key with this public key blob.
key_in_agent() {
    ssh-add -L 2>/dev/null | grep -Fq -- "$1"
}

# Make sure ssh-agent holds the signing key. Without it ssh-keygen falls back to the
# private key file and prompts for its passphrase on every commit. On macOS,
# --apple-load-keychain adds the key using the passphrase already in the Keychain: it
# does not prompt, and re-running it is harmless (the agent keys by fingerprint).
# Arguments: key_blob key_file
ensure_key_in_agent() {
    local key_blob=$1
    local key_file=$2

    if key_in_agent "$key_blob"; then
        print_colored "$COLOR_GREEN" "  key is loaded in ssh-agent"
        return 0
    fi

    if [[ "$OSTYPE" != darwin* ]]; then
        print_colored "$COLOR_YELLOW" "  key is not loaded in ssh-agent (signing will prompt for a passphrase)"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  would run: ssh-add --apple-load-keychain"
        return 0
    fi

    ssh-add --apple-load-keychain >/dev/null 2>&1 || true
    if key_in_agent "$key_blob"; then
        print_colored "$COLOR_GREEN" "  key loaded into ssh-agent from the Keychain"
    else
        note_problem "could not load the key into ssh-agent; store its passphrase once with: ssh-add --apple-use-keychain ${key_file}"
    fi
}

# Verify the key, the allowed signers file, and that a signature can be made and checked.
check_signing_key() {
    local key_file signers_file key_blob test_file signature_file

    key_file=$(setting_or_personal user.signingkey path)
    signers_file=$(setting_or_personal gpg.ssh.allowedSignersFile path)

    if [[ -z "$key_file" || ! -f "$key_file" ]]; then
        note_problem "signing key not found: ${key_file:-<user.signingkey unset>}; copy the key to this computer"
        return 0
    fi
    print_colored "$COLOR_GREEN" "  signing key present: ${key_file}"
    key_blob=$(awk '{print $2}' "$key_file")

    if [[ -z "$signers_file" || ! -f "$signers_file" ]]; then
        note_problem "allowed signers file not found: ${signers_file:-<unset>}"
    elif ! grep -Fq -- "$key_blob" "$signers_file"; then
        note_problem "the signing key is not listed in ${signers_file}; commits will show as unverified locally"
    else
        print_colored "$COLOR_GREEN" "  key is listed in allowed signers"
    fi

    ensure_key_in_agent "$key_blob" "$key_file"

    # Test signature on a scratch file, outside the repository
    scratch_dir=$(mktemp -d)
    test_file="${scratch_dir}/signing-test"
    signature_file="${test_file}.sig"
    printf 'signing test\n' >"$test_file"
    if ssh-keygen -Y sign -f "$key_file" -n git "$test_file" >/dev/null 2>&1 && [[ -f "$signature_file" ]]; then
        print_colored "$COLOR_GREEN" "  test signature succeeded"
    else
        note_problem "could not create a test signature with ${key_file}; is the key loaded (ssh-add) or the passphrase available?"
    fi
}

main() {
    local target="."
    local argument
    for argument in "$@"; do
        case "$argument" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) dry_run=true ;;
            -*) print_colored "$COLOR_RED" "Unknown option: ${argument}"; usage; exit 2 ;;
            *) target=$argument ;;
        esac
    done

    command -v git >/dev/null 2>&1 || die "Required command not found: git"
    command -v ssh-keygen >/dev/null 2>&1 || die "Required command not found: ssh-keygen"
    repo_root=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null) || die "Not a git repository: ${target}"

    print_colored "$COLOR_CYAN" "== ${repo_root}"
    [[ "$dry_run" == true ]] && print_colored "$COLOR_BRIGHTYELLOW" "DRY RUN: the repository will not be modified"

    ensure_signing_config
    check_signing_key

    printf '\n'
    if [[ "$problem_count" -eq 0 ]]; then
        print_colored "$COLOR_GREEN" "Signing is ready for ${repo_root}"
    else
        print_colored "$COLOR_RED" "${problem_count} problem(s) found; signing is not ready"
        return 1
    fi
}

main "$@"
