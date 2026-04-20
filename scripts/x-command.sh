#!/bin/zsh
# x-command.sh - Natural language → shell command via Claude or Codex
# This file should be sourced, not executed directly
# Usage: source ~/mac-config/scripts/x-command.sh
#
# CONFIGURATION:
#   X_PREFER_TOOL     - Which tool to use (default: auto)
#                       Options: "claude" (Claude CLI), "codex" (Codex CLI), "auto" (prefer Claude, fallback to Codex)
#                       Example: export X_PREFER_TOOL=codex
#
#   CODEX_BIN         - Path to Codex executable (default: codex)
#                       Only used if X_PREFER_TOOL=codex or auto (if Claude unavailable)
#                       Example: export CODEX_BIN=/usr/local/bin/codex
#
#   TMPDIR            - Temporary directory for tool output files (default: /tmp)
#                       Standard Unix environment variable, rarely needs to be set
#
# REQUIREMENTS:
#   At least one of: Claude CLI (claude) or Codex CLI (codex) must be installed and authenticated
#   To check: command -v claude  or  command -v codex

# Guard: this library must be sourced, not executed directly.
(return 0 2>/dev/null) || {
    script_name="$(basename "$0")"
    echo "This file is a shell library and must be sourced, not executed." >&2
    echo "Usage: source path/to/${script_name}" >&2
    exit 1
}

ztrace "Loading ${(%):-%x}"

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
function print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

function print_colored_stderr() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n" >&2
}

function cleanup_file() {
    local target_file=$1
    [[ -n "$target_file" && -e "$target_file" ]] && rm -f -- "$target_file"
}

function confirm_execution() {
    local response=''

    if [[ -t 0 ]]; then
        printf 'What do you want to do? [Y/n/c/a] (Yes/No/Copy/Amend): '
        read -r response
    elif [[ -r /dev/tty && -w /dev/tty ]]; then
        printf 'What do you want to do? [Y/n/c/a] (Yes/No/Copy/Amend): ' > /dev/tty
        read -r response < /dev/tty
    else
        print_colored_stderr "$COLOR_RED" 'No interactive terminal is available for confirmation.'
        return 4
    fi

    case "${response:-y}" in
        [Yy]|[Yy][Ee][Ss])
            return 0  # Execute
            ;;
        [Nn]|[Nn][Oo])
            return 1  # Don't execute
            ;;
        [Cc]|[Cc][Oo][Pp][Yy])
            return 2  # Copy to clipboard
            ;;
        [Aa]|[Aa][Mm][Ee][Nn][Dd])
            return 3  # Amend/refine
            ;;
        *)
            print_colored_stderr "$COLOR_YELLOW" "Invalid option. Please choose: Y (Yes), N (No), C (Copy), or A (Amend)"
            confirm_execution  # Recursively ask again
            return $?
            ;;
    esac
}

# ============================================================================
# Tool Detection Functions
# ============================================================================

function detect-claude() {
    local verbose=false

    [[ "$1" == "--verbose" ]] && verbose=true

    # Check if 'claude' command exists and is executable
    if ! command -v claude >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && print_colored_stderr "$COLOR_YELLOW" "Claude CLI not found."
        return 1
    fi

    # Verify Claude CLI responds (basic health check)
    if ! claude --version >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && print_colored_stderr "$COLOR_YELLOW" "Claude CLI is not responding."
        return 1
    fi

    return 0
}

function detect-codex() {
    local verbose=false

    [[ "$1" == "--verbose" ]] && verbose=true

    # Check if codex command exists (or use CODEX_BIN override)
    local codex_bin="${CODEX_BIN:-codex}"

    if ! command -v "$codex_bin" >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && print_colored_stderr "$COLOR_YELLOW" "Codex CLI not found (checked: ${codex_bin})."
        return 1
    fi

    # Verify Codex CLI responds
    if ! "$codex_bin" --version >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && print_colored_stderr "$COLOR_YELLOW" "Codex CLI is not responding."
        return 1
    fi

    return 0
}

# Determine which tool to use: Claude preferred, then Codex, then error
# Respects X_PREFER_TOOL environment variable (values: "claude" or "codex")
function detect-preferred-tool() {
    local prefer="${X_PREFER_TOOL:-auto}"

    case "$prefer" in
        claude)
            detect-claude && echo "claude" && return 0
            print_colored_stderr "$COLOR_RED" "X_PREFER_TOOL=claude but Claude CLI not available."
            return 1
            ;;
        codex)
            detect-codex && echo "codex" && return 0
            print_colored_stderr "$COLOR_RED" "X_PREFER_TOOL=codex but Codex CLI not available."
            return 1
            ;;
        auto)
            # Prefer Claude over Codex (default quiet behavior)
            if detect-claude; then
                echo "claude"
                return 0
            elif detect-codex; then
                echo "codex"
                return 0
            else
                print_colored_stderr "$COLOR_RED" "Neither Claude nor Codex CLI is available."
                print_colored_stderr "$COLOR_YELLOW" "Install Claude (claude) or Codex (codex) CLI, or set X_PREFER_TOOL."
                return 1
            fi
            ;;
        *)
            print_colored_stderr "$COLOR_RED" "Invalid X_PREFER_TOOL value: ${prefer}"
            print_colored_stderr "$COLOR_YELLOW" "Valid values: 'claude', 'codex', or 'auto' (default)"
            return 1
            ;;
    esac
}

# ============================================================================
# Tool Execution Functions
# ============================================================================

# Call Claude CLI and get a command suggestion
function _call_claude() {
    local prompt="$1"
    local cmd

    # Build a specialized prompt for zsh commands
    local full_prompt="You are a shell command assistant for macOS (zsh). Output ONLY a single-line shell command that accomplishes the task. No explanation, no prose, no markdown fences, no surrounding quotes — just the raw command. Task: ${prompt}"

    cmd=$(claude -p --model haiku "$full_prompt" 2>/dev/null)

    # Strip accidental code fences and whitespace
    cmd=$(printf '%s' "$cmd" | sed -e 's/^```[a-zA-Z]*//' -e 's/```$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [[ -z "$cmd" ]]; then
        print_colored_stderr "$COLOR_RED" "Claude returned an empty response."
        return 1
    fi

    printf '%s\n' "$cmd"
    return 0
}

# Call Codex CLI and get a command suggestion
function _call_codex() {
    local prompt="$1"
    local codex_bin="${CODEX_BIN:-codex}"
    local output_file=''
    local cmd_output
    local codex_status

    output_file="$(mktemp "${TMPDIR:-/tmp}/codex-exec-output.XXXXXX")" || {
        print_colored_stderr "$COLOR_RED" 'Failed to create a temporary file for Codex output.'
        return 1
    }

    # Call Codex with the request
    local full_prompt="Return ONLY a shell command (no prose) for: ${prompt}"
    cmd_output="$("$codex_bin" exec --color never --skip-git-repo-check -o "$output_file" "$full_prompt" 2>&1)"
    codex_status=$?

    if (( codex_status != 0 )); then
        print_colored_stderr "$COLOR_RED" "Codex command failed with exit code ${codex_status}."
        if [[ -n "$cmd_output" ]]; then
            print_colored_stderr "$COLOR_RED" 'Codex error:'
            printf '%s\n' "$cmd_output" >&2
        fi
        cleanup_file "$output_file"
        return "$codex_status"
    fi

    cmd_output="$(<"$output_file")"
    cleanup_file "$output_file"

    if [[ -z "${cmd_output//[[:space:]]/}" ]]; then
        print_colored_stderr "$COLOR_RED" 'Codex returned an empty response.'
        return 1
    fi

    printf '%s\n' "$cmd_output"
    return 0
}

# ============================================================================
# Main x() Function - Natural Language to Shell Command
# ============================================================================

function x() {
    if [[ $# -eq 0 ]]; then
        print_colored "$COLOR_YELLOW" 'Usage: x <what you want to do>'
        print_colored "$COLOR_YELLOW" 'Examples:'
        print_colored "$COLOR_YELLOW" '  x list all files starting with .z, non-recursive'
        print_colored "$COLOR_YELLOW" '  x list all files containing "start-here" in ~/dev/projects/ recursively'
        print_colored "$COLOR_YELLOW" '  x replace ".zalaises" with ".zshalias" in all .sh files in this folder'
        return 1
    fi

    local verbose=false
    local request="$*"
    local tool
    local cmd
    local cmd_status
    local confirm_status

    [[ "$1" == "--verbose" ]] && verbose=true

    # Main loop to support amending/refining requests
    while true; do
        # Determine which tool to use
        tool=$(detect-preferred-tool) || return 1

        [[ "$verbose" == "true" ]] && print_colored "$COLOR_CYAN" "Using ${tool} to generate command..."

        # Call the appropriate tool
        case "$tool" in
            claude)
                cmd=$(_call_claude "$request")
                cmd_status=$?
                ;;
            codex)
                cmd=$(_call_codex "$request")
                cmd_status=$?
                ;;
            *)
                print_colored_stderr "$COLOR_RED" "Unknown tool: ${tool}"
                return 1
                ;;
        esac

        if (( cmd_status != 0 )); then
            print_colored_stderr "$COLOR_RED" "Failed to generate command."
            return "$cmd_status"
        fi

        # Display the suggested command
        print_colored "$COLOR_BRIGHTYELLOW" 'Suggested command:'
        printf '%s\n' "$cmd"
        printf '\n'

        # Confirm before executing
        confirm_execution
        confirm_status=$?

        case "$confirm_status" in
            0)
                # Execute
                print_colored "$COLOR_BRIGHTYELLOW" 'Executing command...'
                eval "$cmd"
                return 0
                ;;
            1)
                # Don't execute
                print_colored "$COLOR_YELLOW" 'Command not executed.'
                return 0
                ;;
            2)
                # Copy to clipboard
                if command -v pbcopy >/dev/null 2>&1; then
                    printf '%s' "$cmd" | pbcopy
                    print_colored "$COLOR_GREEN" 'Command copied to clipboard.'
                    return 0
                else
                    print_colored_stderr "$COLOR_RED" 'pbcopy not available. Cannot copy to clipboard.'
                    return 1
                fi
                ;;
            3)
                # Amend/refine - loop back with refined request
                printf '\n'
                print_colored "$COLOR_CYAN" 'Refine your request (added to original):'
                print_colored "$COLOR_YELLOW" "Current: ${request}"
                printf 'Add refinement: '
                read -r refinement

                if [[ -n "$refinement" ]]; then
                    request="${request} ${refinement}"
                    printf '\n'
                    # Loop continues with refined request
                else
                    print_colored "$COLOR_YELLOW" 'No refinement added. Regenerating with original request.'
                    printf '\n'
                fi
                ;;
            *)
                print_colored_stderr "$COLOR_RED" "Unexpected response code: ${confirm_status}"
                return 1
                ;;
        esac
    done
}

# ============================================================================
# Public interface is automatically available in zsh upon sourcing
# ============================================================================
