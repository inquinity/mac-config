#!/bin/zsh

# anchore-functions.sh - Shell library for Anchore Tools / APK search container management
# This file should be sourced, not executed directly
# Usage: source ./anchore-functions.sh

# Guard: this library must be sourced, not executed directly.
_IS_SOURCED=0
if [ -n "${ZSH_VERSION-}" ]; then
    case ${ZSH_EVAL_CONTEXT-} in
        *:file) _IS_SOURCED=1 ;;
    esac
elif [ -n "${BASH_VERSION-}" ]; then
    if [ "${BASH_SOURCE[0]}" != "$0" ]; then
        _IS_SOURCED=1
    fi
else
    (return 0 2>/dev/null) && _IS_SOURCED=1
fi

if [ "$_IS_SOURCED" -ne 1 ]; then
    script_name="$(basename "$0")"
    echo "This file is a shell library and must be sourced, not executed." >&2
    echo "Usage: source path/to/${script_name}" >&2
    exit 1
fi

# Capture script directory at source time.
# In zsh $0 is the sourced file path here (top level); inside functions $0 is the function name.
# Fall back to BASH_SOURCE when running under bash.
if [ -n "${BASH_SOURCE[0]-}" ]; then
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _SCRIPT_DIR="${0:A:h}"
fi

printf "Sourcing $0    Build directory: ${_SCRIPT_DIR}\n"

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

anchore_resolve_image_name() {
    local build_dir="$1"
    local image_name

    if command -v yq >/dev/null 2>&1; then
        image_name=$(yq '.services.service.image' "$build_dir/compose.yml")
        if [ -z "$image_name" ]; then
            image_name="anchore-search:latest"
        fi

        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        print_colored "$COLOR_RED" "Error: Container runtime is not running or not accessible via docker command"
        print_colored "$COLOR_YELLOW" "    Try: docker info"
        return 1
    fi

    return 0
}

anchore_validate_build_prereqs() {
    local build_dir="$1"
    local error_count=0

    if [ ! -d "$build_dir" ]; then
        print_colored "$COLOR_RED" "Error: Build directory does not exist: $build_dir"
        error_count=$((error_count + 1))
    else
        if [ ! -f "$build_dir/Dockerfile" ] && [ ! -f "$build_dir/dockerfile" ]; then
            print_colored "$COLOR_RED" "Error: Dockerfile not found in: $build_dir (expected Dockerfile or dockerfile)"
            error_count=$((error_count + 1))
        fi
    fi

    if [ -z "${ER_AUTH_USER-}" ]; then
        print_colored "$COLOR_RED" "Error: ER_AUTH_USER environment variable not set"
        print_colored "$COLOR_YELLOW" "    Set with: export ER_AUTH_USER=<your-username>"
        error_count=$((error_count + 1))
    fi

    if [ -z "${ER_AUTH_TOKEN-}" ]; then
        print_colored "$COLOR_RED" "Error: ER_AUTH_TOKEN environment variable not set"
        print_colored "$COLOR_YELLOW" "    Set with: export ER_AUTH_TOKEN=<your-token>"
        error_count=$((error_count + 1))
    fi

    if ! anchore_docker_available; then
        error_count=$((error_count + 1))
    fi

    if [ $error_count -gt 0 ]; then
        printf "\n"
        print_colored "$COLOR_YELLOW" "Run 'anchore --help' for more information."
        return 1
    fi

    return 0
}

anchore_ensure_image() {
    local build_dir="$1"
    local image_name="$2"
    local force_rebuild="${3:-0}"
    local max_age_days="${4:-30}"

    if ! anchore_docker_available; then
        return 1
    fi

    if [ "$force_rebuild" -eq 1 ]; then
        anchore_validate_build_prereqs "$build_dir" || return 1
        print_colored "$COLOR_BRIGHTYELLOW" "Force rebuilding image ${image_name}..."
        rebuild_image "$build_dir" "$image_name" || return 1
        return 0
    fi

    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        anchore_validate_build_prereqs "$build_dir" || return 1
        print_colored "$COLOR_BRIGHTYELLOW" "Image ${image_name} not found. Building..."
        rebuild_image "$build_dir" "$image_name" || return 1
        return 0
    fi

    # Check age using LastTagTime when available; fallback to Created for engines that do not expose LastTagTime.
    local last_tag_time created_time tag_date_only timestamp_source
    local current_date_only os_type release_epoch current_epoch age_days
    tag_date_only=""
    timestamp_source=""
    last_tag_time=$(docker image inspect --format='{{ .Metadata.LastTagTime }}' "$image_name" 2>/dev/null)

    if [ -n "$last_tag_time" ] && [ "$last_tag_time" != "<no value>" ] && [ "$last_tag_time" != "0001-01-01T00:00:00Z" ]; then
        tag_date_only="${last_tag_time%%T*}"
        timestamp_source="LastTagTime"
    else
        created_time=$(docker image inspect --format='{{ .Created }}' "$image_name" 2>/dev/null)
        if [ -n "$created_time" ] && [ "$created_time" != "<no value>" ]; then
            tag_date_only="${created_time%%T*}"
            timestamp_source="Created"
        fi
    fi

    if [ -n "$tag_date_only" ]; then
        current_date_only=$(date -u +"%Y-%m-%d")
        os_type=$(uname)

        if [[ "$os_type" == "Darwin" ]]; then
            release_epoch=$(date -j -u -f "%Y-%m-%d" "$tag_date_only" +%s 2>/dev/null)
            current_epoch=$(date -j -u -f "%Y-%m-%d" "$current_date_only" +%s 2>/dev/null)
        else
            release_epoch=$(date -d "$tag_date_only" +%s 2>/dev/null)
            current_epoch=$(date -d "$current_date_only" +%s 2>/dev/null)
        fi

        if [ -n "$release_epoch" ] && [ -n "$current_epoch" ]; then
            age_days=$(( (current_epoch - release_epoch) / 86400 ))
            if [ $age_days -gt $max_age_days ]; then
                anchore_validate_build_prereqs "$build_dir" || return 1
                print_colored "$COLOR_BRIGHTYELLOW" "Image ${image_name} is ${age_days} days old from ${timestamp_source} (older than ${max_age_days} days). Rebuilding..."
                rebuild_image "$build_dir" "$image_name" || return 1
            else
                print_colored "$COLOR_GREEN" "Image ${image_name} is ${age_days} days old from ${timestamp_source} (within ${max_age_days} day limit)."
            fi
        else
            print_colored "$COLOR_YELLOW" "Warning: Could not parse image timestamp (${timestamp_source}=${tag_date_only}). Keeping existing image."
        fi
    else
        print_colored "$COLOR_YELLOW" "Warning: Could not determine image age from metadata. Keeping existing image."
    fi

    return 0
}

anchore_run_scanapk() {
    local image_name="$1"
    shift

    if [ "$#" -eq 0 ]; then
        print_colored "$COLOR_RED" "Error: anchore scanapk requires at least one apk package."
        print_colored "$COLOR_YELLOW" "Usage: anchore scanapk <package> [package ...]"
        return 1
    fi

    print_colored "$COLOR_BRIGHTYELLOW" "Scanning packages: $*"
    print_colored "$COLOR_YELLOW" "Using tools image: ${image_name}"

    docker run \
        --rm \
        --interactive \
        --tty \
        --entrypoint sh \
        --env SCANAPK_NONINTERACTIVE=1 \
        --env SCANAPK_SUPPRESS_REPORT_MESSAGE=1 \
        "$image_name" \
        -ic 'scanapk "$@"; echo ""; echo "Scan complete. Staying in the container so you can inspect the saved files."; exec sh -i' sh "$@"
}

anchore() {
    local build_dir="$_SCRIPT_DIR"
    local image_name
    image_name=$(anchore_resolve_image_name "$build_dir")
    local max_age_days=30
    local force_rebuild=0
    local command_name="shell"
    local -a command_args
    command_args=()

    # Handle help parameter
    if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
        print_colored "$COLOR_GREEN" "Anchore Tools / APK Search Container Manager"
        print_colored "$COLOR_GREEN" "==============================="
        printf "\n"
        print_colored "$COLOR_YELLOW" "DESCRIPTION:"
        printf "    Manages and runs a Wolfi Linux container for Anchore Tools and Wolfi APK package searching.\n"
        printf "    Automatically builds/rebuilds the container image as needed.\n"
        printf "\n"
        print_colored "$COLOR_YELLOW" "Anchore Tools:"
        printf "    syft pre-installed\n"
        printf "    grype pre-installed\n"
        printf "\n"
        
        print_colored "$COLOR_YELLOW" "USAGE:"
        printf "    anchore [OPTION] [scanapk [--summary|--table|--full] <package> [package ...]]\n\n"
        
        print_colored "$COLOR_YELLOW" "OPTIONS:"
        print_colored "$COLOR_BRIGHTYELLOW" "    --help, -h      Show this help message"
        print_colored "$COLOR_BRIGHTYELLOW" "    --rebuild       Force rebuild of the container image"
        print_colored "$COLOR_BRIGHTYELLOW" "    scanapk         Run the in-image apk scanner (default mode: --summary)"
        print_colored "$COLOR_BRIGHTYELLOW" "    (no args)       Run the Anchore Tools container interactively"
        printf "\n"
        
        print_colored "$COLOR_YELLOW" "PREREQUISITES:"
        printf "    - Container runtime accessible via docker command\n"
        printf "    - Build directory exists: %s\n" "$build_dir"
        printf "    - Dockerfile present in build directory\n"
        printf "\n"
        print_colored "$COLOR_YELLOW" "BEHAVIOR:"
        printf "    - Validates prerequisites before proceeding\n"
        printf "    - Checks if image exists, builds if missing\n"
        printf "    - Rebuilds image if older than %d days\n" "$max_age_days"
        printf "    - Runs container in interactive mode with TTY\n\n"
        
        print_colored "$COLOR_YELLOW" "EXAMPLES:"
        print_colored "$COLOR_CYAN" "    anchore              # Run Anchore Tools container"
        print_colored "$COLOR_CYAN" "    anchore --rebuild    # Force rebuild and run"
        print_colored "$COLOR_CYAN" "    anchore scanapk syft        # Summary output"
        print_colored "$COLOR_CYAN" "    anchore scanapk --table syft # Print Syft and Grype tables"
        print_colored "$COLOR_CYAN" "    anchore scanapk --full syft  # Print apk report plus both tables"
        print_colored "$COLOR_CYAN" "    anchore --help       # Show this help"
        return 0
    fi

    print_colored "$COLOR_GREEN" "anchore -- Anchore Tools APK search container"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --rebuild)
                force_rebuild=1
                ;;
            scanapk)
                command_name="scanapk"
                shift
                command_args=("$@")
                break
                ;;
            *)
                print_colored "$COLOR_RED" "Error: Unknown option or command '$1'"
                print_colored "$COLOR_YELLOW" "Run 'anchore --help' for usage."
                return 1
                ;;
        esac
        shift
    done

    anchore_ensure_image "$build_dir" "$image_name" "$force_rebuild" "$max_age_days" || return 1

    if [ "$command_name" = "scanapk" ]; then
        anchore_run_scanapk "$image_name" "${command_args[@]}"
        return $?
    fi

    print_colored "$COLOR_GREEN" "Running ${image_name}..."
    docker run --rm --interactive --tty "$image_name"
}

rebuild_image() {
    local build_dir="$1"
    local image_name="$2"
    local dockerfile_path
    
    if [ ! -d "$build_dir" ]; then
        print_colored "$COLOR_RED" "Error: Build directory ${build_dir} does not exist."
        return 1
    fi

    if [ -f "$build_dir/Dockerfile" ]; then
        dockerfile_path="$build_dir/Dockerfile"
    elif [ -f "$build_dir/dockerfile" ]; then
        dockerfile_path="$build_dir/dockerfile"
    else
        print_colored "$COLOR_RED" "Error: Dockerfile not found in ${build_dir}"
        return 1
    fi
    
    print_colored "$COLOR_BRIGHTYELLOW" "Building image in ${build_dir}..."
    cd "$build_dir" || return 1

    if ! docker build \
        --file "$dockerfile_path" \
        --tag "$image_name" \
        . ; then
        print_colored "$COLOR_RED" "Error: Failed to build image ${image_name}"
        cd - > /dev/null
        return 1
    fi
    
    print_colored "$COLOR_GREEN" "Successfully built ${image_name}"
    cd - > /dev/null
}
