#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.1.6
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/xray.sh

# Requirements:
# 1. jf cli installed

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

# Validate required tool: jf cli
if ! command -v jf &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: jf cli is not installed. Please install docker to use this script." >&2
  exit 1
fi

# Validate parameters
# TBD

# Set variables and save context
image_name="${1}"
datestr="$(date +%Y-%m-%d)"
basestr=$(echo "$(basename ${image_name})" | sed -r "s/:/--/g" )
scan_results="${datestr}_${basestr}_xray.txt"

#echo image_name: ${image_name}
#echo datestr: ${datestr}
#echo basestr: ${basestr}
#echo scan_results: ${scan_results}

if [ -f "${scan_results}" ] ; then
   rm "${scan_results}"
fi

jf docker scan ${image_name} > "${scan_results}"

# Display the results to the console
cat "${scan_results}"
