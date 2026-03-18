# .zshenv is always sourced. It often contains exported variables that should be available to other programs.
# For example, $PATH, $EDITOR, and $PAGER are often set in .zshenv.
# Also, you can set $ZDOTDIR in .zshenv to specify an alternative location for the rest of your zsh configuration.

# Sourced first
# Before .zprofile .zshrc .zlogin

# Other path sources:
# /etc/paths
# /etc/paths.d

# Startup trace: touch ~/.zsh_trace to enable, rm ~/.zsh_trace to disable
[[ -f "${HOME}/.zsh_trace" ]] && ZSH_TRACE=1
ztrace() { (( ${ZSH_TRACE:-0} )) && printf "%s\n" "$*" }

ztrace "Loading ${(%):-%x}"

keychain_service_name() {
    local export_name="$1"
    printf "env/%s" "${(L)export_name}"
}

save_setting_in_keychain() {
    local export_name="$1"
    local service_name
    local setting_value

    if [[ -z "$export_name" ]]; then
        printf "usage: save_setting_in_keychain EXPORT_NAME\n"
        return 2
    fi

    service_name="$(keychain_service_name "$export_name")"
    read -s "setting_value?${export_name}: "
    echo

    if [[ -z "$setting_value" ]]; then
        printf "value is empty: %s\n" "$export_name"
        return 2
    fi

    security add-generic-password -U -s "$service_name" -a default -w "$setting_value"
    unset setting_value
}

load_setting_from_keychain() {
    local export_name="$1"
    local service_name
    local current_value
    local setting_value

    if [[ -z "$export_name" ]]; then
        printf "usage: load_setting_from_keychain EXPORT_NAME\n"
        return 2
    fi

    current_value="${(P)export_name}"
    if [[ -n "$current_value" ]]; then
        return 0
    fi

    service_name="$(keychain_service_name "$export_name")"
    if ! setting_value=$(security find-generic-password -w -s "$service_name" -a default 2>/dev/null); then
        printf "setting not found: %s\n" "$export_name"
        return 1
    fi

    export "$export_name=$setting_value"
}

# define addpath() here since this is the first sourced file
addpath() {
    local input_path=$1
    local dir_path

    case "$input_path" in
        "~") dir_path="$HOME" ;;
        "~/"*) dir_path="$HOME/${input_path#~/}" ;;
        *) dir_path="$input_path" ;;
    esac

    if [ -d "$dir_path" ] && [[ ":$PATH:" != *":$dir_path:"* ]]; then
        export PATH="$dir_path:$PATH"
    fi
}

# Homebrew
# this is repeated in zprofile to ensure correct path ordering so brew folders come before /usr/*/bin
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

add_homebrew_paths

# Docker Desktop paths
if [ -d /Applications/Docker.app ]; then
    addpath ${HOME}/.docker/bin
    addpath /Applications/Docker.app/Contents/Resources/bin/
fi

# Rancher Desktop path
if [ -d ${HOME}/.rd ]; then addpath ${HOME}/.rd/bin ; fi

# Disable Microsoft CLI telemetry
export DOTNET_CLI_TELEMETRY_OPTOUT=1

SHELL_SESSIONS_DISABLE=1

# Load UHG specific settings (if file exists)
source ~/.zshenv-uhg 2> /dev/null
