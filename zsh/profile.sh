# profile.sh
#
# Detects whether this is a "work" (corporate) or "home" computer, by
# hostname prefix. Shared between link-configuration-files.sh (for the
# work/home gitconfig choice) and zshrc (for deciding when to load brew's
# JFrog cool-off wrapper, homebrew.sh), so the two can't drift apart.
CORPORATE_NAME_PREFIX="LAMU"

# Short machine name, with any domain suffix stripped.
computer_name() {
    local raw_name
    raw_name=$(hostname -s 2>/dev/null || uname -n)
    printf '%s' "${raw_name%%.*}"
}

# True when the name begins with CORPORATE_NAME_PREFIX (case-insensitive;
# macOS ships bash 3.2, which has no ${var,,}).
is_corporate_computer() {
    local lowered_name lowered_prefix
    lowered_name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    lowered_prefix=$(printf '%s' "$CORPORATE_NAME_PREFIX" | tr '[:upper:]' '[:lower:]')
    [[ $lowered_name == "$lowered_prefix"* ]]
}

# "work" or "home", from the current hostname.
current_profile() {
    if is_corporate_computer "$(computer_name)"; then
        printf 'work'
    else
        printf 'home'
    fi
}
