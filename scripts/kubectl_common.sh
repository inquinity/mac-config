#!/bin/zsh

# kubectl_common.sh - Common functions for kubectl deployment scripts
# Source this file in your scripts with: source ./path/to/file/kubectl_common.sh

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_TEAL="\e[36m"          # Available for general use
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Date threshold for warning (can be overridden in calling script)
date_threshold_warning=${date_threshold_warning:-25}

# Default jq expression (can be overridden in calling script)
jq_expr=${jq_expr:-'.[0].Config.Labels."golden.container.image.build.release"'}

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Check if arguments are provided
check_arguments() {
    if [ $# -eq 0 ]; then
        print_colored "${COLOR_RED}" "No arguments supplied. Valid arguments: dev, test, prod (or all)."
        exit 1
    fi
}

# Switch kubectl context if needed
switch_context() {
    local target_context=$1
    local current_context=$(kubectl config current-context)
    
    if [ "$current_context" != "$target_context" ]; then
        printf "${COLOR_TEAL}Switching context to: ${target_context}${COLOR_RESET}\n"
        kubectl config use-context $target_context
    fi
}

# Docker inspect with pull-first strategy
# Always pulls to ensure we have the latest image from the registry
# Status messages go to stderr, only the date result goes to stdout
docker_inspect_with_retry() {
    local image_name=$1
    local jq_expr_param=${2:-$jq_expr}
    
    # Always pull first to ensure we have the latest image
    # (image tags can be reused with different content)
    printf "${COLOR_TEAL}    Pulling image: ${image_name}${COLOR_RESET}\n" >&2
    
    if docker pull "$image_name" > /dev/null 2>&1; then
        printf "${COLOR_GREEN}    Successfully pulled image${COLOR_RESET}\n" >&2
    else
        printf "${COLOR_YELLOW}    Pull failed, attempting to use local image if available${COLOR_RESET}\n" >&2
    fi
    
    # Inspect the image
    local result=$(docker inspect "$image_name" 2>/dev/null | jq -r "$jq_expr_param" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ "$result" != "null" ] && [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    
    # Final failure
    printf "${COLOR_RED}    Failed to inspect image: ${image_name}${COLOR_RESET}\n" >&2
    echo "null"
    return 1
}

# Helper function to print release date with color if over threshold days old
print_release_date() {
    local image="$1"
    local jq_expr_param=${2:-$jq_expr}
    local now_epoch=$(date +%s)
    local release_date
    
    release_date=$(docker_inspect_with_retry "$image" "$jq_expr_param")
    
    # Print the Image ID
    local image_id=$(docker inspect --format='{{.Id}}' "$image" 2>/dev/null)
    if [[ -n "$image_id" ]]; then
        printf "    Image ID: %s\n" "$image_id"
    fi
    
    # Print Image Created date with age
    local created_raw=$(docker inspect --format='{{.Created}}' "$image" 2>/dev/null)
    if [[ -n "$created_raw" ]]; then
        # Extract date portion (YYYY-MM-DD) from ISO timestamp
        local created_date="${created_raw:0:10}"
        local created_display="${created_date//-/.}"
        
        # Calculate days old
        local created_epoch=""
        # BSD date (macOS)
        created_epoch=$(date -j -f "%Y-%m-%d" "$created_date" +"%s" 2>/dev/null)
        # GNU date fallback (Linux)
        if [[ -z "$created_epoch" ]]; then
            created_epoch=$(date -d "$created_date" +"%s" 2>/dev/null)
        fi
        
        if [[ -n "$created_epoch" ]]; then
            local created_days=$(( (now_epoch - created_epoch) / 86400 ))
            printf "    Image Created: %s (%s days ago)\n" "$created_display" "$created_days"
        else
            printf "    Image Created: %s\n" "$created_display"
        fi
    fi
    
    if [[ "$release_date" == "null" || -z "$release_date" ]]; then
        printf "    Golden Image Release Date: %s\n" "$release_date"
        return
    fi
    
    # Expecting release_date in format YYYY.MM.DD
    local release_epoch=""
    if [[ "$release_date" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
        # Convert to YYYY-MM-DD for date command
        local release_date_fmt="${release_date//./-}"
        # BSD date (macOS): -j -f "%Y-%m-%d"
        release_epoch=$(date -j -f "%Y-%m-%d" "$release_date_fmt" +"%s" 2>/dev/null)
        # GNU date fallback (Linux): date -d
        if [[ -z "$release_epoch" ]]; then
            release_epoch=$(date -d "$release_date_fmt" +"%s" 2>/dev/null)
        fi
    fi

    local diff_days=""
    if [[ -n "$release_epoch" ]]; then
        diff_days=$(( (now_epoch - release_epoch) / 86400 ))
        if (( diff_days > ${date_threshold_warning} )); then
            printf "    ${COLOR_RED}Golden Image Release Date: %s (%s days old)${COLOR_RESET}\n" "$release_date" "$diff_days"
        else
            printf "    Golden Image Release Date: %s (%s days old)\n" "$release_date" "$diff_days"
        fi
    else
        printf "    Golden Image Release Date: %s\n" "$release_date"
    fi
}

# Get image from deployment/cronjob and print with release date
query_and_print_image() {
    local namespace=$1
    local resource_type=$2  # "deployment" or "cronjob"
    local resource_name=$3
    local jq_expr_param=${4:-$jq_expr}
    
    printf "${COLOR_TEAL}Querying ${resource_type}: ${resource_name}${COLOR_RESET}\n"
    
    local image_name=$(kubectl -n $namespace describe $resource_type $resource_name 2>/dev/null | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g' | head -1)
    if [ -z "$image_name" ]; then
        printf "${COLOR_RED}Failed to get image from ${resource_type}: ${resource_name}${COLOR_RESET}\n"
        return 1
    fi
    
    printf "%s\n" "$image_name"
    print_release_date "$image_name" "$jq_expr_param"
}

# Pull docker image with retry logic and error handling
pull_docker_image() {
    local image_name=$1
    local deployment_type=$2  # "deployment" or "cronjob"
    local resource_name=$3
    
    printf "${COLOR_TEAL}Querying ${deployment_type}: ${resource_name}${COLOR_RESET}\n"
    
    if [ -z "$image_name" ]; then
        printf "${COLOR_RED}Failed to extract image name from ${deployment_type} ${resource_name}${COLOR_RESET}\n"
        return 1
    fi
    
    printf "${COLOR_YELLOW}Pulling image: ${image_name}${COLOR_RESET}\n"
    
    # First attempt
    if docker image pull "$image_name" > /dev/null 2>&1; then
        printf "${COLOR_GREEN}Successfully pulled image: ${image_name}${COLOR_RESET}\n"
        return 0
    fi
    
    printf "${COLOR_YELLOW}First pull attempt failed, retrying with force...${COLOR_RESET}\n"
    
    # Second attempt with force
    if docker image pull "$image_name" --quiet 2>&1; then
        printf "${COLOR_GREEN}Successfully pulled image on retry: ${image_name}${COLOR_RESET}\n"
        return 0
    fi
    
    # Final failure
    printf "${COLOR_RED}Failed to pull image after retry: ${image_name}${COLOR_RESET}\n"
    return 1
}

# Get and pull image from deployment
process_deployment() {
    local namespace=$1
    local deployment_name=$2
    
    local image_name=$(kubectl -n $namespace describe deployment $deployment_name 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*//' | head -1)
    if [ -z "$image_name" ]; then
        printf "${COLOR_RED}Failed to get image from deployment: ${deployment_name}${COLOR_RESET}\n"
        return 1
    fi
    
    pull_docker_image "$image_name" "deployment" "$deployment_name"
}

# Get and pull image from cronjob
process_cronjob() {
    local namespace=$1
    local cronjob_name=$2
    
    local image_name=$(kubectl -n $namespace describe cronjob $cronjob_name 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*//' | head -1)
    if [ -z "$image_name" ]; then
        printf "${COLOR_RED}Failed to get image from cronjob: ${cronjob_name}${COLOR_RESET}\n"
        return 1
    fi
    
    pull_docker_image "$image_name" "cronjob" "$cronjob_name"
}

# Print environment header
print_environment_header() {
    local env_name=$1
    local context=$2
    local namespace=$3
    
    printf "\n${COLOR_BRIGHTYELLOW}Getting information for ${env_name}${COLOR_RESET}\n"
    printf "${COLOR_BRIGHTYELLOW}Context: ${context}${COLOR_RESET}\n"
    printf "${COLOR_BRIGHTYELLOW}Namespace: ${namespace}${COLOR_RESET}\n"
}

# Check if valid argument was found (call at end of script)
check_valid_args() {
    local valid_arg_found=$1
    local invalid_arg=$2
    
    if [ -z "$valid_arg_found" ]; then
        printf "\n${COLOR_RED}Argument \"$invalid_arg\" is not supported; try dev, test, or prod (or all).${COLOR_RESET}\n"
        exit 1
    fi
}
