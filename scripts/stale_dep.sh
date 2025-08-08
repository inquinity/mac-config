#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.0.4
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/scripts/stale_dep.sh

# Requirements:
# * csvkit - https://csvkit.readthedocs.io/en/latest/

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

# Validate required tool: csvkit cli (specifically csvsort)
if ! command -v csvsort &> /dev/null; then
  # Print error if csvkit is not installed
  print_colored "${COLOR_RED}" "Error: cskvit cli is not installed. Please install to use this script." >&2
  exit 1
fi

# Check for required parameters (input CSV files)
if [[ -z "$1" || -z "$2" ]]; then
  print_colored "${COLOR_YELLOW}" "\nUsage: $0 <stale_dependency_file.csv> <stale_packages_file.csv>" >&2
  print_colored "${COLOR_YELLOW}" "\n<stale_dependency_file.csv> has the date" >&2
  print_colored "${COLOR_YELLOW}" "\n<stale_packages_file.csv> has the AID ID" >&2
  exit 1
fi

# Generate the current date in yyyy-mm-dd format for output file naming
current_date=$(date +%Y-%m-%d)
combined_file="${current_date}_stale_dependencies.csv"

# Print input file names
printf "\n"
print_colored "${COLOR_YELLOW}" "Stale dependency file: ${1}"
print_colored "${COLOR_YELLOW}" "Stale Packages file: ${2}"
# printf "${COLOR_YELLOW}Combining stale dependencies and stale packages into ${combined_file}${COLOR_RESET}\n"

# Count rows in each file (excluding header) using csvstat
count1=$(csvstat --count "$1" | tail -n 1)
count2=$(csvstat --count "$2" | tail -n 1)

# Ensure both files have the same number of rows before joining
if [[ "$count1" -ne "$count2" ]]; then
  print_colored "${COLOR_RED}" "Error: Row count mismatch between files." >&2
  print_colored "${COLOR_YELLOW}" "${1}: ${count1} rows" >&2
  print_colored "${COLOR_YELLOW}" "${2}: ${count2} rows" >&2
  exit 1
fi

# Join the two CSV files on their sorted order, select relevant columns, and sort the result
csvjoin --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks \
    <(csvsort --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks "${1}") \
    <(csvsort --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks "${2}") \
| csvcut --delimiter , --quotechar \"  --columns "Dependency Name","Current Version","Release","Latest Version","Recommendation","Tool Identified","Description","Package Details","Remediation","Unique ID","eGRC Vuln Link","View in Security Platform" \
| csvsort --snifflimit 0 --delimiter , --quotechar \" --columns "Recommendation","Dependency Name" > "${combined_file}"

# Count rows in the combined file (using the second input file as reference)
count_combined=$(csvstat --count "$2" | tail -n 1)
# Print summary of combined results
print_colored "${COLOR_YELLOW}" "Combined results: ${combined_file}"
print_colored "${COLOR_YELLOW}" "combined_file: ${count_combined} rows" >&2
