#!/bin/zsh

# Natural language -> shell command suggestion via Codex CLI
# This file should be sourced, not executed directly
# Usage: source ./codex-exec.sh

# Guard: this library must be sourced, not executed directly.
(return 0 2>/dev/null) || {
    script_name="$(basename "$0")"
    echo "This file is a shell library and must be sourced, not executed." >&2
    echo "Usage: source path/to/${script_name}" >&2
    exit 1
}

printf "Sourcing $0...\n"

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

print_colored_stderr() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n" >&2
}

cleanup_file() {
    local target_file=$1
    [[ -n "$target_file" && -e "$target_file" ]] && rm -f -- "$target_file"
}

confirm_execution() {
    local response=''

    if [[ -t 0 ]]; then
        printf 'Execute this command? [y/N] '
        read -r response
    elif [[ -r /dev/tty && -w /dev/tty ]]; then
        printf 'Execute this command? [y/N] ' > /dev/tty
        read -r response < /dev/tty
    else
        print_colored_stderr "$COLOR_RED" 'No interactive terminal is available for confirmation.'
        return 2
    fi

    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

x() {
    if [[ $# -eq 0 ]]; then
        print_colored "$COLOR_YELLOW" 'Usage: x <what you want to do>'
        print_colored "$COLOR_YELLOW" 'Example: x search all files with text "hello world"'
        return 1
    fi

    # Update this if your Codex executable is named differently.
    local codex_bin="${CODEX_BIN:-codex}"

    # Build prompt from all arguments.
    local request="$*"
    local prompt="Return ONLY a shell command (no prose) for: ${request}"
    local output_file=''

    # Ask Codex for a command suggestion.
    if ! command -v "$codex_bin" >/dev/null 2>&1; then
        print_colored_stderr "$COLOR_RED" "Unable to find Codex executable: ${codex_bin}"
        print_colored_stderr "$COLOR_YELLOW" 'Set CODEX_BIN to the correct path or install the Codex CLI.'
        return 127
    fi

    output_file="$(mktemp "${TMPDIR:-/tmp}/codex-exec-output.XXXXXX")" || {
        print_colored_stderr "$COLOR_RED" 'Failed to create a temporary file for Codex output.'
        return 1
    }

    local cmd_output
    local codex_status
    cmd_output="$("$codex_bin" exec --color never --skip-git-repo-check -o "$output_file" "$prompt" 2>&1)"
    codex_status=$?

    if (( codex_status != 0 )); then
        print_colored_stderr "$COLOR_RED" "Codex command failed with exit code ${codex_status}."
        print_colored_stderr "$COLOR_YELLOW" "Executable: ${codex_bin}"
        print_colored_stderr "$COLOR_YELLOW" "Request: ${request}"
        if [[ -n "$cmd_output" ]]; then
            print_colored_stderr "$COLOR_RED" 'Codex output:'
            printf '%s\n' "$cmd_output" >&2
        else
            print_colored_stderr "$COLOR_RED" 'Codex produced no output.'
        fi
        cleanup_file "$output_file"
        return "$codex_status"
    fi

    cmd_output="$(<"$output_file")"
    cleanup_file "$output_file"

    if [[ -z "${cmd_output//[[:space:]]/}" ]]; then
        print_colored_stderr "$COLOR_RED" 'Codex returned an empty response.'
        print_colored_stderr "$COLOR_YELLOW" "Request: ${request}"
        return 1
    fi

    print_colored "$COLOR_BRIGHTYELLOW" 'Suggested command:'
    printf '%s\n' "$cmd_output"

    confirm_execution
    local confirm_status=$?
    if (( confirm_status == 1 )); then
        print_colored "$COLOR_YELLOW" 'Command not executed.'
        return 0
    elif (( confirm_status != 0 )); then
        return "$confirm_status"
    fi

    print_colored "$COLOR_BRIGHTYELLOW" 'Executing command...'
    eval "$cmd_output"
}
