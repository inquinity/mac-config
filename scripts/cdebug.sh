#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.0
# Purpose:
# Automate debugging a running container via cdebug: start IMAGE detached with
# docker, then attach a cdebug sidecar (privileged, interactive) using a
# utility image that provides shell/ps/findutils-style tooling.
#
# Requirements:
# 1. docker (daemon reachable)
# 2. cdebug installed (https://github.com/iximiuz/cdebug)
#
# Usage: cdebug.sh IMAGE [--with UTILITY-IMAGE]

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

DEFAULT_UTILITY_IMAGE="nixery.dev/arm64/shell/apk-tools/ps/findutils:latest"

usage() {
  cat <<EOF
Usage: $(basename "$0") IMAGE [--with UTILITY-IMAGE]

Starts IMAGE detached with docker, then attaches a privileged, interactive
cdebug sidecar built from UTILITY-IMAGE for shell-based debugging.

Arguments:
  IMAGE            Image to run and debug.
  --with IMAGE      Utility image for the cdebug sidecar.
                    Default: ${DEFAULT_UTILITY_IMAGE}

Example:
  $(basename "$0") myregistry.example.com/myapp:latest
  $(basename "$0") myregistry.example.com/myapp:latest --with alpine:latest
EOF
}

image=""
utility_image="${DEFAULT_UTILITY_IMAGE}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0 ;;
    --with)
      if [[ $# -lt 2 ]]; then
        print_colored "$COLOR_RED" "Error: --with requires a UTILITY-IMAGE argument."
        exit 1
      fi
      utility_image="$2"
      shift 2 ;;
    -*)
      print_colored "$COLOR_RED" "Error: unknown option '$1'."
      usage
      exit 1 ;;
    *)
      if [[ -n "$image" ]]; then
        print_colored "$COLOR_RED" "Error: unexpected extra argument '$1'."
        usage
        exit 1
      fi
      image="$1"
      shift ;;
  esac
done

if [[ -z "$image" ]]; then
  print_colored "$COLOR_RED" "Error: IMAGE is required."
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  print_colored "$COLOR_RED" "docker is not installed."
  exit 1
fi

if ! command -v cdebug >/dev/null 2>&1; then
  print_colored "$COLOR_RED" "cdebug is not installed."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  print_colored "$COLOR_RED" "docker daemon is not reachable."
  exit 1
fi

container_id=""

cleanup() {
  if [[ -n "$container_id" ]]; then
    print_colored "$COLOR_YELLOW" "Stopping container ${container_id} ..."
    docker stop "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

print_colored "$COLOR_CYAN" "Starting ${image} (detached) ..."
if ! container_id=$(docker run --rm --tty --detach "$image"); then
  print_colored "$COLOR_RED" "Error: failed to start container from image '${image}'."
  exit 1
fi

print_colored "$COLOR_GREEN" "Container started: ${container_id}"
print_colored "$COLOR_CYAN" "Attaching cdebug (utility image: ${utility_image}) ..."

if ! cdebug exec --privileged -it --image "$utility_image" "$container_id"; then
  print_colored "$COLOR_RED" "Error: cdebug exec failed."
  exit 1
fi
