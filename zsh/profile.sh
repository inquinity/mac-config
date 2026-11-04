# profile.sh
#
# Detects whether this is a "work" (corporate) or "home" computer, by
# hostname prefix. Shared between link-configuration-files.sh (for the
# work/home gitconfig choice) and zshrc (for deciding when to load brew's
# JFrog cool-off wrapper, homebrew.sh), so the two can't drift apart.

# Short machine name, with any domain suffix stripped.
computer_name() {
    local raw_name
    if [[ -n "${ZSH_VERSION:-}" && -n "${HOST:-}" ]]; then
        raw_name=$HOST
    else
        raw_name=$(hostname -s 2>/dev/null || uname -n)
    fi
    printf '%s' "${raw_name%%.*}"
}

# True when the name begins with LAMU (case-insensitive in Bash and zsh).
is_corporate_computer() {
    case "$1" in
        [Ll][Aa][Mm][Uu]*) return 0 ;;
        *) return 1 ;;
    esac
}

# "work" or "home", from the current hostname.
current_profile() {
    if is_corporate_computer "$(computer_name)"; then
        printf 'work'
    else
        printf 'home'
    fi
}
