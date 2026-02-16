#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.0
# Purpose:
# Run dive against an image even when it resides in containerd (nerdctl), by exporting
# to a temporary docker-archive tar and feeding that to dive.
#
# Requirements:
# 1. A container runtime: nerdctl (Rancher Desktop, default namespace assumed) or docker
# 2. dive installed
# 3. mktemp, tar available
#
# Usage: dive.sh [--debug] IMAGE[:TAG] [dive-options...]
# Notes:
#   - Prefers nerdctl (Rancher Desktop, namespace default) then docker.
#   - Uses `command dive` to bypass any shell alias/function named dive.
#   - When docker daemon is available, calls dive directly without export.

set -euo pipefail

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

debug=false
image=""
dive_extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      debug=true; shift ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--debug] <image[:tag]> [dive-options...]
Example: $(basename "$0") edgecore.optum.com/glb-docker-uhg-loc/uhg-goldenimages/chainguard-base:latest
EOF
      exit 0 ;;
    -*)
      dive_extra+=("$1"); shift ;;
    *)
      image="$1"; shift ;;
  esac
done

if [[ -z "$image" ]]; then
  print_colored "$COLOR_RED" "Error: image reference is required."
  exit 1
fi

# If docker daemon is available, just delegate to dive directly
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if [[ "$debug" == true ]]; then
    print_colored "$COLOR_CYAN" "docker available; invoking dive directly"
  fi
  exec command dive "${image}" "${dive_extra[@]}"
fi

# Detect runtime (nerdctl fallback)
CTR_BIN=""
CTR_ARGS=()
NERDCTL_NS=${NERDCTL_NAMESPACE:-default}

if command -v nerdctl >/dev/null 2>&1 && nerdctl --namespace "${NERDCTL_NS}" info >/dev/null 2>&1; then
  CTR_BIN="nerdctl"
  CTR_ARGS=(--namespace "${NERDCTL_NS}")
  print_colored "$COLOR_YELLOW" "Using nerdctl (namespace ${NERDCTL_NS})."
else
  print_colored "$COLOR_RED" "No container runtime available."
  exit 1
fi

ctr() { "${CTR_BIN}" "${CTR_ARGS[@]}" "$@"; }

# Ensure dive exists
if ! command -v dive >/dev/null 2>&1; then
  print_colored "$COLOR_RED" "dive is not installed. Install dive first."
  exit 1
fi

# Pull if missing
if [[ -z "$(ctr image ls -q "${image}" 2>/dev/null)" ]]; then
  print_colored "$COLOR_CYAN" "Pulling image ${image} ..."
  ctr image pull "${image}"
fi

tmp_tar=$(mktemp "./dive-image-XXXX.tar")
cleanup() { rm -f "${tmp_tar}"; }
trap cleanup EXIT

print_colored "$COLOR_CYAN" "Exporting image to ${tmp_tar} ..."
if [[ "$CTR_BIN" == "nerdctl" ]]; then
  nerdctl image save "${image}" -o "${tmp_tar}"
else
  ctr save -o "${tmp_tar}" "${image}"
fi

print_colored "$COLOR_GREEN" "Launching dive ..."
if [[ "$debug" == true ]]; then
  extras=""
  if [[ ${#dive_extra[@]} -gt 0 ]]; then
    extras=" ${dive_extra[*]}"
  fi
  print_colored "$COLOR_CYAN" "command dive docker-archive://${tmp_tar}${extras}"
fi

# Run dive (cleanup occurs on exit trap)
if [[ ${#dive_extra[@]} -gt 0 ]]; then
  command dive "docker-archive://${tmp_tar}" "${dive_extra[@]}"
else
  command dive "docker-archive://${tmp_tar}"
fi

print_colored "$COLOR_GREEN" "dive completed."
