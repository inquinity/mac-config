#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.2
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/docker-scan.sh

# Requirements:
# 1. syft
# 2. grype
# 3. jq
#
# syft sbom generator
# https://github.com/anchore/syft/
# 
# grype vulnerability scanner
# https://github.com/anchore/grype/
#
# Chainguard info on using syft and grype together
# https://edu.chainguard.dev/chainguard/chainguard-images/staying-secure/working-with-scanners/grype-tutorial/

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

# Validate required tool: syft
if ! command -v syft &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: syft is not installed. Please install syft to use this script." >&2
  exit 1
fi

# Validate required tool: grype
if ! command -v grype &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: grype is not installed. Please install grype to use this script." >&2
  exit 1
fi

# Validate required tool: jq
if ! command -v jq &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: jq is not installed. Please install jq to use this script." >&2
  exit 1
fi

# Validate parameters
# TBD

# Set variables and save context
image_name="${1}"
datestr="$(date +%Y-%m-%d)"
basestr=$(echo "$(basename ${image_name})" | sed -r "s/:/--/g" )
sbom="${datestr}_${basestr}_sbom.json"
scan_results="${datestr}_${basestr}_prisma.txt"

#echo image_name: ${image_name}
#echo datestr: ${datestr}
#echo basestr: ${basestr}
#echo username: ${username}
#echo scan_results: ${scan_results}
#echo current_shell: ${current_shell}

#docker inspect ${image_name} > /dev/null 2>&1
#if [ $? -ne 0 ]; then
#  echo "Requested image does not exist."
#  exit 1
#fi
#
#if [ -f "${scan_results}" ] ; then
#   rm "${scan_results}"
#fi

# Run the scan and then pipe all output to a file
print_colored "${COLOR_BLUE}" "Scanning ${image_name}..."
syft scan docker:${image_name} --output syft-json | jq > ${datestr}_${basestr}_sbom.json
cat ${datestr}_${basestr}_sbom.json | grype

#printf "\n"
#printf "Results saved to ${scan_results}\n"

# Display the results to the console
#cat "${scan_results}"
