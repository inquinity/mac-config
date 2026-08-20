#!/usr/bin/env bash
# encryption.sh - Source this file to add encrypt and decrypt shell functions.
#
# Usage:
#   source ~/mac-config/scripts/encryption.sh
#   encrypt [-f] path/to/file [more-files...]
#   decrypt [-f] path/to/file.encrypted [more-files...]
#
# The calling shell expands unquoted glob patterns, for example: encrypt *.txt
# Files are encrypted with OpenSSL AES-256-CBC, PBKDF2-HMAC-SHA256, a random
# salt, and 100,000 iterations. This format is compatible with encryption.ps1.

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

encryption_extension="encrypted"
encryption_pbkdf2_iterations="100000"

encryption_usage() {
    print_colored "$COLOR_YELLOW" "Usage: encrypt [-f] file [file ...]"
    print_colored "$COLOR_YELLOW" "       decrypt [-f] file.encrypted [file.encrypted ...]"
    print_colored "$COLOR_YELLOW" "Without -f, an existing output file is never replaced."
}

encryption_require_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        print_colored "$COLOR_RED" "OpenSSL is required. Install a current version with Homebrew or Chocolatey."
        return 1
    fi
}

encryption_read_password() {
    local confirmation_required=$1

    printf 'Please enter a password: '
    IFS= read -r -s encryption_password
    printf '\n'

    if [ "$confirmation_required" = "true" ]; then
        local password_confirmation
        printf 'Please re-enter the password: '
        IFS= read -r -s password_confirmation
        printf '\n'

        if [ "$encryption_password" != "$password_confirmation" ]; then
            encryption_password=""
            print_colored "$COLOR_RED" "Passwords do not match."
            return 1
        fi
    fi
}

encryption_parse_options() {
    encryption_force_overwrite=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f|--force)
                encryption_force_overwrite=true
                shift
                ;;
            -h|--help)
                encryption_usage
                return 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                print_colored "$COLOR_RED" "Unknown option: $1"
                encryption_usage
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    encryption_paths=("$@")
    if [ "${#encryption_paths[@]}" -eq 0 ]; then
        print_colored "$COLOR_RED" "At least one file is required."
        encryption_usage
        return 1
    fi
}

encryption_run_openssl() {
    local mode=$1
    local input_file=$2
    local output_file=$3

    if [ "$mode" = "encrypt" ]; then
        printf '%s\n' "$encryption_password" | openssl enc -aes-256-cbc -salt -pbkdf2 \
            -iter "$encryption_pbkdf2_iterations" -md sha256 -in "$input_file" \
            -out "$output_file" -pass stdin
    else
        printf '%s\n' "$encryption_password" | openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -iter "$encryption_pbkdf2_iterations" -md sha256 -in "$input_file" \
            -out "$output_file" -pass stdin
    fi
}

encryption_process_file() {
    local mode=$1
    local source_file=$2
    local destination_file temporary_file

    if [ ! -f "$source_file" ]; then
        print_colored "$COLOR_RED" "Not a regular file: $source_file"
        return 1
    fi

    if [ "$mode" = "encrypt" ]; then
        if [[ "$source_file" == *".${encryption_extension}" ]]; then
            print_colored "$COLOR_YELLOW" "Skipping $source_file; it already ends with .${encryption_extension}."
            return 0
        fi
        destination_file="${source_file}.${encryption_extension}"
    else
        if [[ "$source_file" != *".${encryption_extension}" ]]; then
            print_colored "$COLOR_YELLOW" "Skipping $source_file; it does not end with .${encryption_extension}."
            return 0
        fi
        destination_file="${source_file%.$encryption_extension}"
    fi

    if [ -e "$destination_file" ] && [ "$encryption_force_overwrite" != "true" ]; then
        print_colored "$COLOR_RED" "Refusing to replace existing file: $destination_file (use -f to overwrite)"
        return 1
    fi

    temporary_file=$(mktemp "${destination_file}.tmp.XXXXXX") || {
        print_colored "$COLOR_RED" "Unable to create a temporary output file for: $destination_file"
        return 1
    }

    if [ "$mode" = "encrypt" ]; then
        print_colored "$COLOR_BRIGHTYELLOW" "Encrypting $source_file"
    else
        print_colored "$COLOR_BRIGHTYELLOW" "Decrypting $source_file"
    fi
    if ! encryption_run_openssl "$mode" "$source_file" "$temporary_file"; then
        rm -f "$temporary_file"
        print_colored "$COLOR_RED" "Unable to ${mode} $source_file. Check the password and OpenSSL version."
        return 1
    fi

    if ! mv -f "$temporary_file" "$destination_file"; then
        rm -f "$temporary_file"
        print_colored "$COLOR_RED" "Unable to save output file: $destination_file"
        return 1
    fi

    print_colored "$COLOR_GREEN" "Successfully ${mode}ed $source_file -> $destination_file"
}

encryption_process() {
    local mode=$1
    shift
    local parse_status file overall_status=0

    encryption_parse_options "$@"
    parse_status=$?
    if [ "$parse_status" -eq 2 ]; then
        return 0
    elif [ "$parse_status" -ne 0 ]; then
        return "$parse_status"
    fi

    encryption_require_openssl || return 1
    if [ "$mode" = "encrypt" ]; then
        encryption_read_password true || return 1
    else
        encryption_read_password false || return 1
    fi

    for file in "${encryption_paths[@]}"; do
        encryption_process_file "$mode" "$file" || overall_status=1
    done

    encryption_password=""
    return "$overall_status"
}

encrypt() {
    encryption_process encrypt "$@"
}

decrypt() {
    encryption_process decrypt "$@"
}
