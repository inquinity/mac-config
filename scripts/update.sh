#! /bin/zsh

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BLUE="\e[34m"          # Available for general use
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Upgrade homebrew formulas and casks
if command -v brew &> /dev/null; then
  print_colored "${COLOR_BRIGHTYELLOW}" "Starting brew upgrade"
  brew update
  brew upgrade
  print_colored "${COLOR_GREEN}" "Completed"
else
  print_colored "${COLOR_YELLOW}" "Brew is not installed. Skipping brew upgrade."
fi
printf "\n"

# Update grype database
if command -v grype &> /dev/null; then
  print_colored "${COLOR_BRIGHTYELLOW}" "Updating grype database"
  grype db update
  print_colored "${COLOR_GREEN}" "Completed"
else
  print_colored "${COLOR_YELLOW}" "Grype is not installed. Skipping grype database update."
fi
printf "\n"

# Update CodeQL test suites
if [[ -d ~/dev/codeql ]]; then
  print_colored "${COLOR_BRIGHTYELLOW}" "Updating CodeQL repository"
  pushd ~/dev/codeql
  git pull
  popd
  print_colored "${COLOR_GREEN}" "Completed"
else
  print_colored "${COLOR_YELLOW}" "CodeQL directory not found at ~/dev/codeql. Skipping CodeQL update."
fi
printf "\n"

# Clean docker images and containers
if command -v docker &> /dev/null; then
  print_colored "${COLOR_BRIGHTYELLOW}" "Cleaning docker images and containers"
  # Check if there are any dangling volumes
  dangling_volumes=$(docker volume ls --filter=dangling=true --quiet)

  if [ -n "$dangling_volumes" ]; then
    # If there are dangling volumes, remove them
    docker volume rm $(docker volume ls --filter=dangling=true --quiet)
  else
    print_colored "${COLOR_YELLOW}" "No dangling volumes to remove."
  fi

  # Check if there are any dangling images
  dangling_images=$(docker images --filter=dangling=true --quiet)

  if [ -n "$dangling_images" ]; then
    # If there are dangling images, remove them
    docker rmi $(docker images --filter=dangling=true --quiet)
  else
    print_colored "${COLOR_YELLOW}" "No dangling images to remove."
  fi
else
  print_colored "${COLOR_YELLOW}" "Docker is not installed. Skipping docker cleanup."
fi

