#!/bin/zsh
# docker.sh - Context-switched container helpers (prefer nerdctl, fallback dockerd)
# This file should be sourced, not executed directly
# Usage: source ~/mac-config/scripts/docker.sh

# Guard: this library must be sourced, not executed directly.
(return 0 2>/dev/null) || {
    script_name="$(basename "$0")"
    echo "This file is a shell library and must be sourced, not executed." >&2
    echo "Usage: source path/to/${script_name}" >&2
    exit 1
}

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

# Load backend libraries directly so this file is self-contained.
DOCKER_LIB_FILE="${${(%):-%N}:A}"
DOCKER_LIB_DIR="${DOCKER_LIB_FILE:h}"
if [[ -f "${DOCKER_LIB_DIR}/nerdctl.sh" ]]; then
    source "${DOCKER_LIB_DIR}/nerdctl.sh"
fi
if [[ -f "${DOCKER_LIB_DIR}/dockerdaemon.sh" ]]; then
    source "${DOCKER_LIB_DIR}/dockerdaemon.sh"
fi

# Always allow calling the real docker CLI explicitly
alias dockerd='command docker'

CONTAINER_ENGINE_CACHE_TTL=${CONTAINER_ENGINE_CACHE_TTL:-3}
CONTAINER_ENGINE_CACHE=""
CONTAINER_ENGINE_CACHE_TS=0

get_container_engine() {
    local quiet=false
    local refresh=false
    local now
    local arg

    for arg in "$@"; do
        case "$arg" in
            --quiet) quiet=true ;;
            --refresh) refresh=true ;;
        esac
    done

    now=${EPOCHSECONDS:-$(date +%s)}
    if [[ "${refresh}" != "true" ]] && [[ -n "${CONTAINER_ENGINE_CACHE}" ]] && (( now - CONTAINER_ENGINE_CACHE_TS < CONTAINER_ENGINE_CACHE_TTL )); then
        echo "${CONTAINER_ENGINE_CACHE}"
        return 0
    fi

    if whence -w nerdctl_ready >/dev/null 2>&1 && nerdctl_ready --quiet; then
        CONTAINER_ENGINE_CACHE="nerdctl"
        CONTAINER_ENGINE_CACHE_TS=${now}
        echo "nerdctl"
        return 0
    fi

    if whence -w dockerdaemon_ready >/dev/null 2>&1 && dockerdaemon_ready --quiet; then
        CONTAINER_ENGINE_CACHE="dockerd"
        CONTAINER_ENGINE_CACHE_TS=${now}
        echo "dockerd"
        return 0
    fi

    # Fallback for hosts that only have a plain docker daemon and no helper libs.
    if whence -p docker >/dev/null 2>&1 && command docker info >/dev/null 2>&1; then
        CONTAINER_ENGINE_CACHE="dockerd"
        CONTAINER_ENGINE_CACHE_TS=${now}
        echo "dockerd"
        return 0
    fi

    CONTAINER_ENGINE_CACHE=""
    CONTAINER_ENGINE_CACHE_TS=${now}
    [[ "${quiet}" != "true" ]] && print_colored "$COLOR_RED" "No container runtime engine found (tried nerdctl then dockerd)."
    return 1
}

docker() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        command nerdctl --namespace "${NERDCTL_NS:-${NERDCTL_NAMESPACE:-default}}" "$@"
    else
        command docker "$@"
    fi
}

docker-ls() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        nerdctl-ls "$@"
    else
        dockerd-ls "$@"
    fi
}

docker-sha() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        nerdctl-sha "$@"
    else
        dockerd-sha "$@"
    fi
}

docker-os() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        nerdctl-os "$@"
    else
        dockerd-os "$@"
    fi
}

docker-info() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        nerdctl-info "$@"
    else
        dockerd-info "$@"
    fi
}

docker-run() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        nerdctl-run "$@"
    else
        dockerd-run "$@"
    fi
}

docker-exec() {
    local engine
    engine=$(get_container_engine) || return 1

    if [[ "${engine}" == "nerdctl" ]]; then
        nerdctl-exec "$@"
    else
        dockerd-exec "$@"
    fi
}
