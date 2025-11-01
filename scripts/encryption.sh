#!/bin/bash
# encryption.shlib - Shell library for file encryption/decryption functions
# This file should be sourced, not executed directly
# Usage: source ~/mac-config/encryption.shlib

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

# printf "Sourcing encryption.shlib...\n"

encryption_extension="encrypted"

encrypt() {
    # Prompt for password
    IFS= read -rs 'password?Please enter a password: '
    printf "\n"
    IFS= read -rs 'password2?Please re-enter the password: '
    printf "\n"

    if [ "$password" != "$password2" ]; then
        print_colored "$COLOR_RED" "Passwords do not match. Exiting."
        exit 1
    fi

    # make sure we don't encrypt the same file twice
    seen_files=()

    # walk through the files and encrypt them
    for pattern in "$@"; do
        for file in ${pattern}; do
            # space are needed in the comparison to avoid matching substrings
            if [[ ! " ${seen_files[*]} " =~ " ${file} " ]]; then
                # skip files that already end with .encrypted
                if [[ "${file}" == *.${encryption_extension} ]]; then
                    print_colored "$COLOR_YELLOW" "Skipping ${file} as it already ends with .${encryption_extension}"
                    continue
                fi
                # create the encrypted file name
                encrypted_name="${file}.${encryption_extension}"
                print_colored "$COLOR_BLUE" "Encrypting ${file} to ${encrypted_name}"
                # remove the encrypted file if it exists
                if [ -f "${encrypted_name}" ]; then
                    rm "${encrypted_name}"
                fi
                # encrypt the file
                if ! openssl aes-256-cbc -in "${file}" -out "${encrypted_name}" -pass pass:"${password}"; then
                    print_colored "$COLOR_RED" "Error encrypting ${file}"
                    [ -f "${encrypted_name}" ] && rm "${encrypted_name}"
                else
                    print_colored "$COLOR_GREEN" "Successfully encrypted ${file}"
                fi
                # add the file to the seen files
                seen_files+=("${file}")
            fi
        done
    done
}

decrypt() {
    # Prompt for password
    IFS= read -rs 'password?Please enter a password: '
    printf "\n"

    # make sure we don't decrypt the same file twice
    seen_files=()

    # walk through the files and decrypt them
    for pattern in "$@"; do
        for file in ${pattern}; do
            # space are needed in the comparison to avoid matching substrings
            if [[ ! " ${seen_files[*]} " =~ " ${file} " ]]; then
                # ensure the file ends with encryption_extension
                if [[ ! "${file}" == *.${encryption_extension} ]]; then
                    print_colored "$COLOR_YELLOW" "${file} does not end with .${encryption_extension}"
                else
                    # decrypt the file
                    decrypted_name="${file%.$encryption_extension}"
                    # remove the decrypted file if it exists
                    if [ -f "${decrypted_name}" ]; then
                        rm "${decrypted_name}"
                    fi
                    print_colored "$COLOR_BLUE" "Decrypting ${file} to ${decrypted_name}"
                    if ! openssl aes-256-cbc -d -in "${file}" -out "${decrypted_name}" -pass pass:"${password}"; then
                        print_colored "$COLOR_RED" "Error decrypting ${file}"
                        [ -f "${decrypted_name}" ] && rm "${decrypted_name}"
                    else
                        print_colored "$COLOR_GREEN" "Successfully decrypted ${file}"
                    fi
                fi
                seen_files+=("${file}")
            fi
        done
    done
}
