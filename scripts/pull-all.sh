#!/bin/zsh

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

# Check for optional subdirectory parameter
if [ $# -eq 1 ]; then
    subdirectory="$1"
    # Check for help request
    if [ "$subdirectory" = "help" ] || [ "$subdirectory" = "-h" ] || [ "$subdirectory" = "--help" ]; then
        print_colored "${COLOR_YELLOW}" "Usage: $0 [subdirectory]"
        print_colored "${COLOR_YELLOW}" "Examples:"
        print_colored "${COLOR_YELLOW}" "  $0          # Update all git repositories"
        print_colored "${COLOR_YELLOW}" "  $0 team     # Update only repositories in ./team directory"
        exit 0
    fi
    if [ ! -d "$subdirectory" ]; then
        print_colored "${COLOR_RED}" "Error: Subdirectory '$subdirectory' not found."
        exit 1
    fi
    print_colored "${COLOR_BRIGHTYELLOW}" "Starting pull-all script for subdirectory: $subdirectory"
    search_path="./$subdirectory"
elif [ $# -eq 0 ]; then
    print_colored "${COLOR_BRIGHTYELLOW}" "Starting pull-all script for all directories"
    search_path="."
else
    print_colored "${COLOR_RED}" "Usage: $0 [subdirectory]"
    print_colored "${COLOR_YELLOW}" "Examples:"
    print_colored "${COLOR_YELLOW}" "  $0          # Update all git repositories"
    print_colored "${COLOR_YELLOW}" "  $0 team     # Update only repositories in ./team directory"
    exit 1
fi

find "$search_path" -type d -name ".git" -execdir zsh -c '
     COLOR_GREEN="\e[32m"; COLOR_RESET="\e[0m"
     print_colored() { local color=$1; local message=$2; printf "${color}${message}${COLOR_RESET}\n"; }
     print_colored "${COLOR_GREEN}" "$(pwd)"
     git pull
' \;
