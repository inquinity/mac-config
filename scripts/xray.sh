#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.2.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/xray.sh

# Requirements:
# 1. jf cli installed
# 2. docker daemon reachable (jf docker scan requires docker daemon)

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

RUNTIME_NERDCTL_NS="${NERDCTL_NAMESPACE:-default}"

if ! command -v jf >/dev/null 2>&1; then
  print_colored "${COLOR_RED}" "Error: jf cli is not installed."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  print_colored "${COLOR_RED}" "Error: docker cli is not installed."
  exit 1
fi

if ! command docker info >/dev/null 2>&1; then
  if command -v nerdctl >/dev/null 2>&1 && command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" info >/dev/null 2>&1; then
    print_colored "${COLOR_RED}" "Containerd-only mode is unsupported for xray/jf docker scan."
    print_colored "${COLOR_YELLOW}" "Enable dockerd mode (Rancher Desktop Moby) or start a docker daemon and retry."
  else
    print_colored "${COLOR_RED}" "Docker daemon is unreachable. Start Docker or enable dockerd in Rancher Desktop (Moby)."
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
    tmp_tar="$(mktemp "${TMPDIR:-/tmp}/xray-image-XXXX.tar")"
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
scan_results="${datestr}_${basestr}_xray.txt"

rm -f "${scan_results}"

if ! jf docker scan "${image_name}" > "${scan_results}"; then
  print_colored "${COLOR_RED}" "Xray scan failed."
  exit 1
fi

cat "${scan_results}"
