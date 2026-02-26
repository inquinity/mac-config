#!/bin/zsh
# dockerdaemon.sh - Shell library for Docker daemon management functions
# This file should be sourced, not executed directly
# Usage: source ~/mac-config/scripts/dockerdaemon.sh

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

# Ensure Docker CLI and daemon are reachable before running commands
DOCKERDAEMON_READY_CACHE_TTL=${DOCKERDAEMON_READY_CACHE_TTL:-3}
DOCKERDAEMON_READY_CACHE_STATE=""
DOCKERDAEMON_READY_CACHE_TS=0

dockerdaemon_ready() {
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
    if [[ "${refresh}" != "true" ]] && (( now - DOCKERDAEMON_READY_CACHE_TS < DOCKERDAEMON_READY_CACHE_TTL )); then
        [[ "${DOCKERDAEMON_READY_CACHE_STATE}" == "ok" ]] && return 0 || return 1
    fi

    if ! whence -p docker >/dev/null 2>&1; then
        DOCKERDAEMON_READY_CACHE_STATE="down"
        DOCKERDAEMON_READY_CACHE_TS=${now}
        [[ "${quiet}" != "true" ]] && print_colored "$COLOR_RED" "docker CLI not found."
        return 1
    fi

    if ! command docker info >/dev/null 2>&1; then
        DOCKERDAEMON_READY_CACHE_STATE="down"
        DOCKERDAEMON_READY_CACHE_TS=${now}
        [[ "${quiet}" != "true" ]] && print_colored "$COLOR_YELLOW" "docker daemon/socket is unreachable."
        return 1
    fi

    DOCKERDAEMON_READY_CACHE_STATE="ok"
    DOCKERDAEMON_READY_CACHE_TS=${now}
    return 0
}

dockerd-ls() {
    dockerdaemon_ready || return 1

    local format_args="{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}\t{{.ID}}\t{{.Size}}"
    if [ -n "$1" ]; then
        local result
        result=$(command docker image ls --format "${format_args}")
        for term in "$@"; do
            result=$(printf "%s" "$result" | fgrep "$term")
        done
        printf "%s\n" "$result"
    else
        command docker image ls --format "${format_args}"
    fi
}

dockerd-sha() {
    dockerdaemon_ready || return 1
    command docker inspect "$1" | jq '"Image: "+.[0].Id, "Repository: "+.[0].RepoDigests[0]'
}

dockerd-os() {
    dockerdaemon_ready || return 1
    command docker run --rm --interactive --tty --entrypoint "sh" --user root "$1" -c "grep ^ID= /etc/os-release | cut -c 4-"
}

dockerd-info() {
    dockerdaemon_ready || return 1
    printf "Inspecting Docker image: %s\n" "$1"
    command docker inspect "$1" | jq -r '.[0] | "
    Instance ID: " + .Id + "
    Full Resource Name: " + .RepoDigests[0] + "
    Image Build Date: " + .Created + "
    Golden Image Type: " + .Config.Labels["golden.container.image.type"] + "
    Golden Image Build Tag: " + .Config.Labels["golden.container.image.build.tag"] + "
    Golden Image Release Date: " + .Config.Labels["golden.container.image.build.release"] + "
    Chainguard Package: " + .Config.Labels["dev.chainguard.package.main"] + "
    Chainguard Image Base: " + .Config.Labels["golden.container.image.vendor.tag"] + "
    Image Source: " + .Config.Labels["org.opencontainers.image.source"]
'
}

dockerd-run() {
    dockerdaemon_ready || return 1
    command docker run --rm --interactive --tty --entrypoint "sh" --user root "$1"
}

dockerd-exec() {
    dockerdaemon_ready || return 1
    command docker exec --interactive --tty "$1" sh
}
