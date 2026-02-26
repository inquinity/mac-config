#! /bin/zsh

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

# Load foundational container runtime libraries (if available)
SCRIPT_DIR="${0:A:h}"
RUNTIME_LIB_DIR="${SCRIPT_DIR}"
if [[ ! -f "${RUNTIME_LIB_DIR}/nerdctl.sh" && -d "${HOME}/mac-config/scripts" ]]; then
  RUNTIME_LIB_DIR="${HOME}/mac-config/scripts"
fi
if [[ -f "${RUNTIME_LIB_DIR}/nerdctl.sh" ]]; then source "${RUNTIME_LIB_DIR}/nerdctl.sh"; fi
if [[ -f "${RUNTIME_LIB_DIR}/dockerdaemon.sh" ]]; then source "${RUNTIME_LIB_DIR}/dockerdaemon.sh"; fi

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
  if ! whence -w dockerdaemon_ready >/dev/null 2>&1; then
    return
  fi

  if ! dockerdaemon_ready --quiet; then
    return
  fi

  print_colored "${COLOR_BRIGHTYELLOW}" "Pruning Docker dangling volumes and images"
  command docker volume prune --force >/dev/null 2>&1
  command docker image prune --force >/dev/null 2>&1
  print_colored "${COLOR_GREEN}" "Docker prune completed."
}

cleanup_nerdctl() {
  if ! whence -w nerdctl_ready >/dev/null 2>&1; then
    return
  fi

  if ! command -v nerdctl >/dev/null 2>&1; then
    return
  fi

  if ! nerdctl_ready --quiet; then
    return
  fi

  # First pass: exactly what you run manually.
  print_colored "${COLOR_BRIGHTYELLOW}" "Pruning nerdctl dangling volumes and images (default CLI context)"
  command nerdctl volume prune --force >/dev/null 2>&1
  command nerdctl image prune --force >/dev/null 2>&1
  print_colored "${COLOR_GREEN}" "nerdctl prune completed (default context)."

  # Secondary pass: sweep explicit namespaces to catch drift.
  local default_ns="${NERDCTL_NS:-${NERDCTL_NAMESPACE:-default}}"
  local ns
  local ns_list_raw
  local -a namespaces

  ns_list_raw="$(command nerdctl namespace ls --quiet 2>/dev/null)"
  if [ -n "${ns_list_raw}" ]; then
    namespaces=( ${(f)ns_list_raw} )
  else
    namespaces=( "${default_ns}" )
  fi

  for ns in "${namespaces[@]}"; do
    # default context already handled above
    if [[ "${ns}" == "${default_ns}" ]]; then
      continue
    fi

    print_colored "${COLOR_BRIGHTYELLOW}" "Pruning nerdctl (namespace ${ns}) dangling volumes and images"
    command nerdctl --namespace "${ns}" volume prune --force >/dev/null 2>&1
    command nerdctl --namespace "${ns}" image prune --force >/dev/null 2>&1
    print_colored "${COLOR_GREEN}" "nerdctl prune completed in namespace ${ns}."
  done
}

cleanup_docker
cleanup_nerdctl
