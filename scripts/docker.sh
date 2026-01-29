#!/bin/bash
# docker.shlib - Shell library for Docker container management functions
# This file should be sourced, not executed directly
# Usage: source ~/mac-config/docker.shlib

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

# printf "Sourcing docker.shlib...\n"

docker-ls() {
    # Detect container runtime type
    runtimes=$(docker info 2>/dev/null | grep "Runtimes:" | awk '{print $2}')
    if [ "$runtimes" = "io.containerd.runc.v2" ]; then
        print_colored "$COLOR_YELLOW" "Using containerd"
    else
        print_colored "$COLOR_YELLOW" "Using standard container"
    fi
    
    format_args="{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}\t{{.ID}}\t{{.Size}}"
    if [ -n "$1" ]; then
        result=$(docker image ls --format "${format_args}")
        for term in "$@"; do
            result=$(printf "%s" "$result" | fgrep "$term")
        done
        printf "%s\n" "$result"
    else
        docker image ls --format "${format_args}"
    fi
}

docker-sha() { 
    docker inspect "$1" | jq '"Image: "+.[0].Id, "Repository: "+.[0].RepoDigests[0]' 
}

docker-os() { 
    docker run --rm --interactive --tty --entrypoint "sh" --user root "$1" -c "grep ^ID= /etc/os-release | cut -c 4-" 
}

docker-info() {
    printf "Inspecting Docker image: %s\n" "$1"
    docker inspect "$1" | jq -r '.[0] | "
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

docker-run() { 
    docker run --rm --interactive --tty --entrypoint "sh" --user root "$1" 
}

docker-exec() { 
    docker exec --interactive --tty "$1" sh 
}
