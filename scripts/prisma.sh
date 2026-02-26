#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.1.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/prisma.sh

# Requirements:
# 1. twistcli installed
# 2. user must have Prisma Compute permissions in secure
# 3. docker daemon reachable (twistcli images scan requires docker daemon)
#
# Prisma Compute (aka Twistlock) info: https://enterprise-cloud-security.optum.com/cloud-security/prisma-compute

set -o pipefail

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

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <image-reference>

Example:
  $(basename "$0") edgecore.optum.com/path/image:tag
EOF
}

prisma_url="https://myapplications.microsoft.com/"
twistlock_address="https://us-east1.cloud.twistlock.com/us-2-158257717"
RUNTIME_NERDCTL_NS="${NERDCTL_NAMESPACE:-default}"

show_instructions() {
  print_colored "${COLOR_MAGENTA}" "Opening browser to ${prisma_url}"
  print_colored "${COLOR_MAGENTA}" "Navigate to Redlock application using optumcloud ID"
  print_colored "${COLOR_MAGENTA}" "Select System, under Manage in left menu, and copy the token details"
}

get_prisma_token() {
  prisma_token=""
  if command -v open >/dev/null 2>&1; then
    open "${prisma_url}" >/dev/null 2>&1
  fi
  vared -p "Paste token: " prisma_token
}

if ! command -v twistcli >/dev/null 2>&1; then
  print_colored "${COLOR_RED}" "Error: twistcli is not installed. Please install twistcli to use this script."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  print_colored "${COLOR_RED}" "Error: docker cli is not installed. Prisma twistcli requires a docker daemon."
  exit 1
fi

if ! command docker info >/dev/null 2>&1; then
  if command -v nerdctl >/dev/null 2>&1 && command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" info >/dev/null 2>&1; then
    print_colored "${COLOR_RED}" "Containerd-only mode is unsupported for prisma/twistcli scanning."
    print_colored "${COLOR_YELLOW}" "Enable dockerd mode (Rancher Desktop Moby) or start a docker daemon and retry."
  else
    print_colored "${COLOR_RED}" "Docker daemon is unreachable. Start Docker or enable dockerd in Rancher Desktop (Moby) to use twistcli."
  fi
  exit 1
fi

image_name="${1}"
if [ -z "${image_name}" ] || [[ "${image_name}" == "-h" ]] || [[ "${image_name}" == "--help" ]]; then
  usage
  exit 1
fi

if ! command docker image inspect "${image_name}" >/dev/null 2>&1; then
  if command -v nerdctl >/dev/null 2>&1 && command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" image inspect "${image_name}" >/dev/null 2>&1; then
    print_colored "${COLOR_YELLOW}" "Image not present in docker; found in nerdctl. Exporting and loading into docker..."
    tmp_tar="$(mktemp "${TMPDIR:-/tmp}/prisma-image-XXXX.tar")"
    if command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" image save "${image_name}" -o "${tmp_tar}" && command docker load -i "${tmp_tar}" >/dev/null 2>&1; then
      rm -f "${tmp_tar}"
      print_colored "${COLOR_GREEN}" "Image loaded into docker for scanning."
    else
      rm -f "${tmp_tar}"
      print_colored "${COLOR_RED}" "Failed to stage image from nerdctl to docker."
      exit 1
    fi
  else
    print_colored "${COLOR_BLUE}" "Image not present locally in docker. Pulling ${image_name}..."
    if ! command docker pull "${image_name}" >/dev/null 2>&1; then
      print_colored "${COLOR_RED}" "Requested image does not exist locally and pull failed."
      exit 1
    fi
  fi
fi

datestr="$(date +%Y-%m-%d)"
basestr="$(basename "${image_name}" | sed -E 's/:/--/g')"
scan_results="${datestr}_${basestr}_prisma.txt"

rm -f "${scan_results}"

if [ -z "${PRISMA}" ]; then
  show_instructions
  get_prisma_token
  print_colored "${COLOR_YELLOW}" "You can save the token by executing: export PRISMA=<token>"
  print_colored "${COLOR_YELLOW}" "Tokens are valid for 1 hour."
else
  prisma_token="${PRISMA}"
fi

if [ -z "${prisma_token}" ]; then
  print_colored "${COLOR_RED}" "No Prisma token provided."
  exit 1
fi

print_colored "${COLOR_BLUE}" "Scanning ${image_name}..."
if ! twistcli images scan --address "${twistlock_address}" --token "${prisma_token}" "${image_name}" | sed '1,3d' > "${scan_results}"; then
  print_colored "${COLOR_RED}" "Prisma scan failed."
  exit 1
fi

print_colored "${COLOR_GREEN}" "Results saved to ${scan_results}"
cat "${scan_results}"
