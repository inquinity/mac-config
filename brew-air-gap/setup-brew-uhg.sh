#!/bin/bash

# UHG Homebrew Setup Script
# Sets up Homebrew with UHG/Artifactory configuration

set -e

# Color output helpers
tty_bold="$(tput bold 2>/dev/null)" || tty_bold=""
tty_underline="$(tput smul 2>/dev/null)" || tty_underline=""
tty_reset="$(tput sgr0 2>/dev/null)" || tty_reset=""

ohai() {
  printf "${tty_bold}==>${tty_reset} %s\n" "$@"
}

abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

warn() {
  printf "%s\n" "$@" >&2
}

# Check for Xcode Command Line Tools
check_xcode_clt() {
  if ! xcode-select --print-path &>/dev/null; then
    abort "$(
      cat <<EOABORT
Xcode Command Line Tools are required but not installed.

Please install them using UHG Self-Service:

1. Open Self Service application on your Mac
2. Search for "Xcode Command Line Tools"
3. Click Install

After installation, please re-run this script.
EOABORT
    )"
  fi
}

# Determine the appropriate shell config file to modify
get_shell_rcfile() {
  case "${SHELL}" in
    */bash*)
      echo "${HOME}/.bash_profile"
      ;;
    */zsh*)
      echo "${ZDOTDIR:-"${HOME}"}/.zprofile"
      ;;
    */fish*)
      echo "${HOME}/.config/fish/config.fish"
      ;;
    *)
      echo "${HOME}/.profile"
      ;;
  esac
}

# Ensure rc file exists
ensure_rcfile() {
  if [[ ! -f "$1" ]]; then
    touch "$1"
  fi
}

# Add or replace an export in a file
set_or_replace_export() {
  local var_name="$1"
  local var_value="$2"
  local file="$3"
  local value_escaped
  
  # Properly quote the value
  printf -v value_escaped '%q' "${var_value}"
  local line="export ${var_name}=${value_escaped}"

  if grep -qs "^export ${var_name}=" "${file}"; then
    # Replace existing
    /usr/bin/sed -i '' -e "s|^export ${var_name}=.*|${line}|" "${file}"
  else
    # Add new line
    printf "%s\n" "${line}" >> "${file}"
  fi
}

# Main script
main() {
  ohai "UHG Homebrew Setup"
  echo

  # Step 1: Check for Xcode Command Line Tools
  ohai "Checking for Xcode Command Line Tools..."
  check_xcode_clt
  echo "✓ Xcode Command Line Tools are installed"
  echo

  # Get the shell rc file
  shell_rcfile="$(get_shell_rcfile)"
  ensure_rcfile "${shell_rcfile}"

  # Step 2: Ask for repo1 token
  ohai "Artifactory Token Configuration"
  printf "Please paste your repo1 Artifactory token: "
  IFS= read -rs artifactory_token
  echo
  
  if [[ -z "${artifactory_token}" ]]; then
    abort "No Artifactory token provided. Cannot continue."
  fi
  echo

  # Step 3: Add exports to startup scripts
  ohai "Configuring shell environment..."
  
  set_or_replace_export "HOMEBREW_ARTIFACT_DOMAIN" "https://repo1.uhc.com/artifactory/homebrew" "${shell_rcfile}"
  set_or_replace_export "HOMEBREW_DOCKER_REGISTRY_TOKEN" "${artifactory_token}" "${shell_rcfile}"
  set_or_replace_export "HOMEBREW_NO_INSTALL_FROM_API" "1" "${shell_rcfile}"
  
  echo "✓ Added Homebrew environment variables to ${shell_rcfile}"
  echo

  # Step 4: Export to current shell so Homebrew installer can use them
  ohai "Loading environment variables in current shell..."
  export HOMEBREW_ARTIFACT_DOMAIN="https://repo1.uhc.com/artifactory/homebrew"
  export HOMEBREW_DOCKER_REGISTRY_TOKEN="${artifactory_token}"
  export HOMEBREW_NO_INSTALL_FROM_API="1"
  echo "✓ Environment variables are now active in this shell"
  echo

  # Step 5: Run Homebrew installer
  ohai "Installing Homebrew..."
  echo "This may take a few minutes..."
  echo
  
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    echo
    ohai "Installation successful!"
  else
    abort "Homebrew installation failed. Please check your network connection and try again."
  fi

  # Step 6: Add brew shellenv to shell rc file
  ohai "Configuring shell profile file..."
  
  # Add brew shellenv line to profile file if not already present
  if ! grep -qsF 'eval "$(brew shellenv' "${shell_rcfile}"; then
    eval "$($(which brew) shellenv)" >> /dev/null 2>&1 || true
    printf "%s\n" 'eval "$($(which brew) shellenv)"' >> "${shell_rcfile}"
    echo "✓ Added brew shellenv to ${shell_rcfile}"
  fi
  echo

  # Step 7: Completion message
  echo
  ohai "Setup Complete!"
  echo "$(
    cat <<EOS
${tty_bold}Next Steps:${tty_reset}

Your shell environment has been configured with the following:
  - HOMEBREW_ARTIFACT_DOMAIN=https://repo1.uhc.com/artifactory/homebrew
  - HOMEBREW_DOCKER_REGISTRY_TOKEN=<your_token>
  - HOMEBREW_NO_INSTALL_FROM_API=1

These settings have been added to: ${shell_rcfile}

${tty_bold}To complete setup:${tty_reset}
1. ${tty_underline}Start a new terminal window${tty_reset} to load the new environment variables
2. Run ${tty_bold}brew help${tty_reset} to verify the installation
3. Run ${tty_bold}brew install${tty_reset} <formula> to start installing packages

For more information about Homebrew:
  ${tty_underline}https://docs.brew.sh${tty_reset}

For UHG Homebrew/Artifactory configuration:
  ${tty_underline}https://engineeringsupportportal.uhg.com/platform?nav=JFROG?subNav=MIRRORING_HOMEBREW${tty_reset}
EOS
  )
"
}

# Run main function
main "$@"
