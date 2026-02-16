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

# Clean container images and volumes (Docker + Rancher Desktop)
cleanup_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    return
  fi

  print_colored "${COLOR_BRIGHTYELLOW}" "Cleaning Docker dangling volumes and images"

  local dangling_volumes
  dangling_volumes=$(docker volume ls --filter dangling=true --quiet 2>/dev/null | tr '\n' ' ')
  if [ -n "${dangling_volumes}" ]; then
    docker volume rm ${dangling_volumes} >/dev/null 2>&1
  else
    print_colored "${COLOR_YELLOW}" "No dangling Docker volumes to remove."
  fi

  local dangling_images
  dangling_images=$(docker images --filter dangling=true --quiet 2>/dev/null | tr '\n' ' ')
  if [ -n "${dangling_images}" ]; then
    docker rmi ${dangling_images} >/dev/null 2>&1
  else
    print_colored "${COLOR_YELLOW}" "No dangling Docker images to remove."
  fi
}

cleanup_nerdctl() {
  if ! command -v nerdctl >/dev/null 2>&1; then
    return
  fi

  local ns="${NERDCTL_NAMESPACE:-k8s.io}"

  if ! nerdctl --namespace "${ns}" info >/dev/null 2>&1; then
    return
  fi

  print_colored "${COLOR_BRIGHTYELLOW}" "Cleaning nerdctl (namespace ${ns}) dangling volumes and images"

  local dangling_volumes
  dangling_volumes=$(nerdctl --namespace "${ns}" volume ls --filter dangling=true --quiet 2>/dev/null | tr '\n' ' ')
  if [ -n "${dangling_volumes}" ]; then
    nerdctl --namespace "${ns}" volume rm ${dangling_volumes} >/dev/null 2>&1
  else
    print_colored "${COLOR_YELLOW}" "No dangling nerdctl volumes to remove."
  fi

  local dangling_images
  dangling_images=$(nerdctl --namespace "${ns}" images --filter dangling=true --quiet 2>/dev/null | tr '\n' ' ')
  if [ -n "${dangling_images}" ]; then
    nerdctl --namespace "${ns}" rmi ${dangling_images} >/dev/null 2>&1
  else
    print_colored "${COLOR_YELLOW}" "No dangling nerdctl images to remove."
  fi
}

cleanup_docker
cleanup_nerdctl
