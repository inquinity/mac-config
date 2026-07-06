# brew shellenv output is cached in $_BREW_SHELLENV_CACHE so child shells skip the brew call.
add_homebrew_paths() {
    if [[ $CPUTYPE == arm64 ]]; then
        # Apple chips
        if [[ -z "${_BREW_SHELLENV_CACHE:-}" ]]; then
            export _BREW_SHELLENV_CACHE="$(/opt/homebrew/bin/brew shellenv)"
        fi
        eval "$_BREW_SHELLENV_CACHE"
        addpath "/opt/bin"
        if [[ -d /opt/homebrew/opt/mysql-client/bin ]]; then
            addpath "/opt/homebrew/opt/mysql-client/bin"
        fi
    else
        # Intel chips
        addpath "/usr/local/sbin"
    fi
}
