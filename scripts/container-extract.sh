#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.1.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/container-extract.sh

# Requirements:
# * Container runtime: nerdctl (Rancher Desktop, default namespace) or docker
# * tar installed

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

RUNTIME_BIN=""
RUNTIME_NERDCTL_NS="${NERDCTL_NAMESPACE:-default}"

runtime_cmd() {
  if [[ "${RUNTIME_BIN}" == "nerdctl" ]]; then
    command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" "$@"
  else
    command docker "$@"
  fi
}

runtime_image_inspect() {
  local image_ref="$1"
  runtime_cmd image inspect "${image_ref}" >/dev/null 2>&1
}

detect_runtime_for_image() {
  local image_ref="$1"

  if command -v docker >/dev/null 2>&1 && command docker image inspect "${image_ref}" >/dev/null 2>&1; then
    RUNTIME_BIN="docker"
    print_colored "${COLOR_YELLOW}" "Using docker daemon."
    return 0
  fi

  if command -v nerdctl >/dev/null 2>&1 && command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" image inspect "${image_ref}" >/dev/null 2>&1; then
    RUNTIME_BIN="nerdctl"
    print_colored "${COLOR_YELLOW}" "Using nerdctl (namespace ${RUNTIME_NERDCTL_NS})."
    return 0
  fi

  if command -v nerdctl >/dev/null 2>&1 && command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" info >/dev/null 2>&1; then
    RUNTIME_BIN="nerdctl"
    print_colored "${COLOR_YELLOW}" "Using nerdctl (namespace ${RUNTIME_NERDCTL_NS})."
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && command docker info >/dev/null 2>&1; then
    RUNTIME_BIN="docker"
    print_colored "${COLOR_YELLOW}" "Using docker daemon."
    return 0
  fi

  print_colored "${COLOR_RED}" "No container runtime engine found."
  return 1
}

is_sha256() {
  if [ -z "$1" ]; then
    return 1
  fi
  [[ "$1" =~ ^[a-f0-9]{12}$|^[a-f0-9]{64}$ ]]
}

if ! command -v tar >/dev/null 2>&1; then
  print_colored "${COLOR_RED}" "Error: tar is not installed."
  exit 1
fi

image_name="${1}"
if [ -z "${image_name}" ] || [[ "${image_name}" == "-h" ]] || [[ "${image_name}" == "--help" ]]; then
  usage
  exit 1
fi

detect_runtime_for_image "${image_name}" || exit 1

extract_type="container"
image_folder="$(basename "${image_name}" | sed 's/:/--/').${extract_type}"
image_tar="${image_folder}.tar"

if [ -d "${image_folder}" ]; then
  print_colored "${COLOR_YELLOW}" "Clearing old folder..."
  rm -rf "${image_folder}"
fi
mkdir -p "${image_folder}"

if ! is_sha256 "${image_name}" && ! runtime_image_inspect "${image_name}"; then
  print_colored "${COLOR_BLUE}" "Pulling image ${image_name}"
  if ! runtime_cmd pull "${image_name}"; then
    print_colored "${COLOR_RED}" "Could not pull image; exiting"
    rm -rf "${image_folder}"
    exit 1
  fi
fi

print_colored "${COLOR_BLUE}" "Starting container for image ${image_name}"
container_id=""
run_status=0
if [[ "${RUNTIME_BIN}" == "nerdctl" ]]; then
  run_cmd=(command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" run -d --entrypoint sh "${image_name}")
  print_colored "${COLOR_BLUE}" "Run command: ${run_cmd[*]}"
  container_id="$("${run_cmd[@]}" 2>/dev/null)" || run_status=$?
  if [ ${run_status} -ne 0 ] || [ -z "${container_id}" ]; then
    run_status=0
    run_cmd=(command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" run -d "${image_name}")
    print_colored "${COLOR_BLUE}" "Fallback run command: ${run_cmd[*]}"
    container_id="$("${run_cmd[@]}" 2>/dev/null)" || run_status=$?
  fi
else
  run_cmd=(command docker run -d -i --rm --entrypoint sh "${image_name}")
  print_colored "${COLOR_BLUE}" "Run command: ${run_cmd[*]}"
  container_id="$("${run_cmd[@]}" 2>/dev/null)" || run_status=$?
  if [ ${run_status} -ne 0 ] || [ -z "${container_id}" ]; then
    run_status=0
    run_cmd=(command docker run -d -i --rm "${image_name}")
    print_colored "${COLOR_BLUE}" "Fallback run command: ${run_cmd[*]}"
    container_id="$("${run_cmd[@]}" 2>/dev/null)" || run_status=$?
  fi
fi

if [ ${run_status} -ne 0 ] || [ -z "${container_id}" ]; then
  print_colored "${COLOR_RED}" "Container could not be started; exiting"
  rm -rf "${image_folder}"
  exit 1
fi
print_colored "${COLOR_GREEN}" "Container ID: ${container_id}"

print_colored "${COLOR_BLUE}" "Writing filesystem to ${image_tar}"
if ! runtime_cmd export --output="${image_tar}" "${container_id}"; then
  print_colored "${COLOR_RED}" "Export failed; exiting"
  rm -rf "${image_folder}"
  exit 1
fi

print_colored "${COLOR_BLUE}" "Stopping container ${container_id}"
runtime_cmd stop "${container_id}" >/dev/null 2>&1 || print_colored "${COLOR_YELLOW}" "Error stopping container; continuing."
if [[ "${RUNTIME_BIN}" == "nerdctl" ]]; then
  runtime_cmd rm -f "${container_id}" >/dev/null 2>&1
fi

print_colored "${COLOR_BLUE}" "Extracting image to disk..."
tar_status=0
tar -xpf "${image_tar}" --exclude='dev/*' -C "${image_folder}" >/dev/null 2>&1 || tar_status=$?

if [ ${tar_status} -eq 0 ]; then
  print_colored "${COLOR_GREEN}" "Container extract completed successfully: ${image_folder}"
  exit 0
fi

print_colored "${COLOR_YELLOW}" "Container extract completed with warnings/errors (tar exit ${tar_status})."
exit ${tar_status}
