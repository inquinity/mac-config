#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.0.6
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/prisma.sh

# Requirements:
# 1. twistcli installed
# 2. user must have Prisma Compute permissions in secure
#
# Prisma Compute (aka Twistlock) info: https://enterprise-cloud-security.optum.com/cloud-security/prisma-compute

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

prisma_url="https://myapplications.microsoft.com/"

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

show_instructions() {
    print_colored "${COLOR_MAGENTA}" "Opening browser to ${prisma_url}"
    print_colored "${COLOR_MAGENTA}" "Navigate to Redlock application using optumcloud ID"
    print_colored "${COLOR_MAGENTA}" "Select System, under Manage in left menu, and copy the token details"
}

get_prisma_token() {
  prisma_token=
  open "${prisma_url}"
  # Request the password, using the correct bash or zsh syntax
  if [ "$current_shell" = "bash" ]; then
    # read -s -p "bash-Please enter the token: " password
    # Some options: https://superuser.com/questions/593476/what-is-the-bash-equivalent-of-zsh-vared-command
    print_colored "${COLOR_RED}" "bash does not support reading 1600 character tokens"
    print_colored "${COLOR_YELLOW}" "You will need to export the token by hand and re-run this script."
    print_colored "${COLOR_YELLOW}" "You can save the token by executing: export PRISMA=token"
    exit 2
  elif [ "$current_shell" = "zsh" ]; then
    vared -p "Paste token: " prisma_token
  else
    print_colored "${COLOR_RED}" "Unknown shell: ${current_shell}"
    exit 3
  fi
}

# Validate required tool: twistcli
if ! command -v twistcli &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: twistcli is not installed. Please install twistcli to use this script." >&2
  exit 1
fi

# Validate required tool: docker
if ! command -v docker &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: docker cli is not installed. Please install docker cli to use this script." >&2
  exit 1
fi

# Validate parameters
# TBD

# Set variables and save context
image_name="${1}"
username=${USER}
datestr="$(date +%Y-%m-%d)"
basestr=$(echo "$(basename ${image_name})" | sed -r "s/:/--/g" )
scan_results="${datestr}_${basestr}_prisma.txt"
current_shell=$(basename $(ps -p $$ -o comm=))

#printf "image_name: ${image_name}\n"
#printf "datestr: ${datestr}\n"
#printf "basestr: ${basestr}\n"
#printf "username: ${username}\n"
#printf "scan_results: ${scan_results}\n"
#printf "current_shell: ${current_shell}\n"

docker inspect ${image_name} > /dev/null 2>&1
if [ $? -ne 0 ]; then
  print_colored "${COLOR_RED}" "Requested image does not exist."
  exit 1
fi

# Clean up any previous scan results
if [ -f "${scan_results}" ] ; then
   rm "${scan_results}"
fi

# Check if the Prisma token is set in the environment
if [ -z "${PRISMA}" ]; then
  show_instructions
  get_prisma_token
  print_colored "${COLOR_YELLOW}" "You can save the token by executing: export PRISMA=token..."
  print_colored "${COLOR_YELLOW}" "Tokens are valid for 1 hour"
else
  prisma_token="${PRISMA}"
fi

# the --output-file FILE.txt option will output a JSON detail, but is hard to read
# Run the scan and then pipe all output to a file
print_colored "${COLOR_BLUE}" "Scanning ${image_name}..."
twistcli images scan --address  https://us-east1.cloud.twistlock.com/us-2-158257717 --token ${prisma_token} ${image_name} | sed '1,3d' > "${scan_results}"

print_colored "${COLOR_GREEN}" "Results saved to ${scan_results}"

# Display the results to the console
cat "${scan_results}"

# To automatically open the results in Chrome, uncomment the following lines...
# results_url=$(grep Link "${scan_results}" | sed -r "s/Link.*http/http/g")
# open -n -a "Google Chrome" --args '--new-window' "${results_url}"
