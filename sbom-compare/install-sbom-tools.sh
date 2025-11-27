#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.1
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/docker/sbom-compare/install-sbom-tools.sh

# Installation script for SBOM comparison tools

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Update print_colored function to use printf
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Update installation directory based on system architecture
if [[ $(uname -m) == "arm64" ]]; then
    INSTALL_DIR="/opt/bin"
    if [ ! -d "/opt/bin" ]; then
        print_colored ${COLOR_YELLOW} "Creating /opt/bin directory..."
        sudo mkdir -p "/opt/bin"
    fi
else
    INSTALL_DIR="/usr/bin"
fi

printf "\n"

# Check if install dir exists, create if not
if [ ! -d "${INSTALL_DIR}" ]; then
    print_colored ${COLOR_YELLOW} "Creating ${INSTALL_DIR} directory..."
    mkdir -p "${INSTALL_DIR}"
fi

# Check if install dir is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    print_colored ${COLOR_YELLOW} "Adding ${INSTALL_DIR} to PATH..."
    printf "\n" >> "${HOME}/.zshrc"
    printf "# Added by SBOM tools installer\n" >> "${HOME}/.zshrc"
    printf "export PATH=\"${INSTALL_DIR}:\$PATH\"\n" >> "${HOME}/.zshrc"
    
    # Also add to .bashrc if it exists
    if [ -f "${HOME}/.bashrc" ]; then
        printf "\n" >> "${HOME}/.bashrc"
        printf "# Added by SBOM tools installer\n" >> "${HOME}/.bashrc"
        printf "export PATH=\"${INSTALL_DIR}:\$PATH\"\n" >> "${HOME}/.bashrc"
    fi
    
    print_colored ${COLOR_GREEN} "PATH updated. Please restart your terminal or run: source ~/.zshrc"
fi

# Copy scripts to install dir
print_colored "${COLOR_BLUE}" "Installing SBOM tools to ${INSTALL_DIR}..."

sudo cp "${SCRIPT_DIR}/sbom-diff.sh" "${INSTALL_DIR}/sbom-diff"
sudo cp "${SCRIPT_DIR}/sbom-analyze.sh" "${INSTALL_DIR}/sbom-analyze"

# Make sure they're executable
sudo chmod +x "${INSTALL_DIR}/sbom-diff"
sudo chmod +x "${INSTALL_DIR}/sbom-analyze"

print_colored "${COLOR_GREEN}" "✓ sbom-diff installed"
print_colored "${COLOR_GREEN}" "✓ sbom-analyze installed"

# Check dependencies
print_colored "${COLOR_BLUE}" "Checking dependencies..."

missing_deps=()

if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
fi

if ! command -v syft &> /dev/null; then
    missing_deps+=("syft")
fi

if [ ${#missing_deps[@]} -eq 0 ]; then
    print_colored ${COLOR_GREEN} "✓ All dependencies are installed"
else
    print_colored ${COLOR_YELLOW} "Missing dependencies: ${missing_deps[*]}"
    printf "\n"
    printf "To install missing dependencies:\n"
    
    for dep in "${missing_deps[@]}"; do
        case $dep in
            "jq")
                printf "  jq:\n"
                printf "    macOS: brew install jq\n"
                printf "    Ubuntu/Debian: sudo apt-get install jq\n"
                printf "    CentOS/RHEL: sudo yum install jq\n"
                ;;
            "syft")
                printf "  syft:\n"
                printf "    macOS: brew install syft\n"
                printf "    Linux: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin\n"
                ;;
        esac
    done
fi

printf "\n"
print_colored "${COLOR_GREEN}" "=== Installation Complete ==="
print_colored "${COLOR_BLUE}" "Usage:"
printf "  sbom-diff <image1> <image2>     # Compare two Docker images\n"
printf "  sbom-analyze <sbom1> <sbom2>       # Analyze two SBOM files\n"
printf "\n"
print_colored "${COLOR_BLUE}" "Examples:"
printf "  sbom-diff ubuntu:20.04 ubuntu:22.04\n"
printf "  sbom-analyze image1.json image2.json --detailed\n"
printf "\n"
print_colored "${COLOR_YELLOW}" "Note: If this is your first installation, restart your terminal or run:"
print_colored "${COLOR_YELLOW}" "  source ~/.zshrc"
