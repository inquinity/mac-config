#!/bin/zsh
# nerdctl.sh - Shell library for Rancher Desktop / nerdctl container management functions
# This file should be sourced, not executed directly
# Usage: source ~/mac-config/scripts/nerdctl.sh

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

# Namespace used by Rancher Desktop's containerd
# User images typically live in the \"default\" namespace; Rancher system/K8s images in \"k8s.io\".
NERDCTL_NS=${NERDCTL_NAMESPACE:-default}
NERDCTL_READY_CACHE_TTL=${NERDCTL_READY_CACHE_TTL:-3}
NERDCTL_READY_CACHE_STATE=""
NERDCTL_READY_CACHE_TS=0

# Utility to ensure nerdctl + daemon are reachable before running a command
nerdctl_ready() {
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
    if [[ "${refresh}" != "true" ]] && (( now - NERDCTL_READY_CACHE_TS < NERDCTL_READY_CACHE_TTL )); then
        [[ "${NERDCTL_READY_CACHE_STATE}" == "ok" ]] && return 0 || return 1
    fi

    if ! whence -p nerdctl >/dev/null 2>&1; then
        NERDCTL_READY_CACHE_STATE="down"
        NERDCTL_READY_CACHE_TS=${now}
        [[ "${quiet}" != "true" ]] && print_colored "$COLOR_RED" "nerdctl not found in PATH."
        return 1
    fi

    if ! command nerdctl --namespace "${NERDCTL_NS}" info >/dev/null 2>&1; then
        NERDCTL_READY_CACHE_STATE="down"
        NERDCTL_READY_CACHE_TS=${now}
        [[ "${quiet}" != "true" ]] && print_colored "$COLOR_RED" "namespace '${NERDCTL_NS}' is unreachable."
        return 1
    fi

    NERDCTL_READY_CACHE_STATE="ok"
    NERDCTL_READY_CACHE_TS=${now}
    return 0
}

nerdctl-ls() {
    nerdctl_ready || return 1

    # nerdctl's Go template doesn't interpret escape sequences, so embed real tabs
    local format_args=$'{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}\t{{.ID}}\t{{.Size}}'
    local tab=$'\t'

    if [ -n "$1" ]; then
        result=$(nerdctl --namespace "${NERDCTL_NS}" image ls --format "${format_args}")
        for term in "$@"; do
            result=$(printf "%s" "$result" | fgrep "$term")
        done
        printf "%s\n" "$result" | column -t -s "${tab}"
    else
        nerdctl --namespace "${NERDCTL_NS}" image ls --format "${format_args}" | column -t -s "${tab}"
    fi
}

nerdctl-sha() {
    nerdctl_ready || return 1
    nerdctl --namespace "${NERDCTL_NS}" image inspect "$1" | jq '"Image: "+.[0].Id, "Repository: "+.[0].RepoDigests[0]'
}

nerdctl-os() {
    nerdctl_ready || return 1
    nerdctl --namespace "${NERDCTL_NS}" run --rm --interactive --tty --entrypoint "sh" --user root "$1" -c "grep ^ID= /etc/os-release | cut -c 4-"
}

nerdctl-info() {
    nerdctl_ready || return 1
    printf "Inspecting nerdctl image: %s\n" "$1"
    nerdctl --namespace "${NERDCTL_NS}" image inspect "$1" | jq -r '.[0] | "
    Instance ID: " + .Id + "
    Full Resource Name: " + (.RepoDigests[0] // "n/a") + "
    Image Build Date: " + .Created + "
    Golden Image Type: " + .Config.Labels["golden.container.image.type"] + "
    Golden Image Build Tag: " + .Config.Labels["golden.container.image.build.tag"] + "
    Golden Image Release Date: " + .Config.Labels["golden.container.image.build.release"] + "
    Chainguard Package: " + .Config.Labels["dev.chainguard.package.main"] + "
    Chainguard Image Base: " + .Config.Labels["golden.container.image.vendor.tag"] + "
    Image Source: " + .Config.Labels["org.opencontainers.image.source"]
' 
}

nerdctl-run() {
    nerdctl_ready || return 1
    nerdctl --namespace "${NERDCTL_NS}" run --rm --interactive --tty --entrypoint "sh" --user root "$1"
}

nerdctl-exec() {
    nerdctl_ready || return 1
    nerdctl --namespace "${NERDCTL_NS}" exec --interactive --tty "$1" sh
}
