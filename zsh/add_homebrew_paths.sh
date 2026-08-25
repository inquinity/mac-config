# brew shellenv output is cached in $_BREW_SHELLENV_CACHE so child shells skip the brew call.
#
# Safe to call more than once: the addpath calls use --move, so a second invocation
# re-asserts precedence rather than silently no-opping. .zprofile relies on this
# because /etc/zprofile runs path_helper between .zshenv and .zprofile.
add_homebrew_paths() {
    if [[ $CPUTYPE == arm64 ]]; then
        # Apple chips
        if [[ -z "${_BREW_SHELLENV_CACHE:-}" ]]; then
            export _BREW_SHELLENV_CACHE="$(/opt/homebrew/bin/brew shellenv)"
        fi
        # Keg-only formulae go on first so that the brew shellenv eval below, which
        # prepends unconditionally, still leaves /opt/homebrew/bin ahead of them.
        if [[ -d /opt/homebrew/opt/mysql-client/bin ]]; then
            addpath --move "/opt/homebrew/opt/mysql-client/bin"
        fi
        eval "$_BREW_SHELLENV_CACHE"
    else
        # Intel chips
        addpath --move "/usr/local/sbin"
    fi
}
