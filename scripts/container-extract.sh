#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.0.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/container-extract.sh

# Requirements:
# * Container runtime: nerdctl (Rancher Desktop, default namespace) or docker

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

# Detect container runtime (prefer nerdctl default namespace)
CTR_BIN=""
CTR_ARGS=()
NERDCTL_NS=${NERDCTL_NAMESPACE:-default}

detect_container_runtime() {
  if command -v nerdctl >/dev/null 2>&1 && nerdctl --namespace "${NERDCTL_NS}" info >/dev/null 2>&1; then
    CTR_BIN="nerdctl"
    CTR_ARGS=(--namespace "${NERDCTL_NS}")
    print_colored "${COLOR_YELLOW}" "Using nerdctl (namespace ${NERDCTL_NS})."
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    CTR_BIN="docker"
    CTR_ARGS=()
    print_colored "${COLOR_YELLOW}" "Using docker daemon."
    return 0
  fi

  print_colored "${COLOR_RED}" "No container runtime daemon reachable (tried nerdctl then docker)."
  return 1
}

ctr() {
  "${CTR_BIN}" "${CTR_ARGS[@]}" "$@"
}

is_sha256()
{
    # Validate parameters
    if [ -z "$1" ]; then
      return 0
    fi

    [[ "$1" =~ ^[a-f0-9]{12}$|^[a-f0-9]{64}$ ]]
    return $?
}

detect_container_runtime || exit 1

# Validate required tool: jq
if ! command -v jq &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: jq is not installed. Please install jq to use this script." >&2
  exit 1
fi

# Validate parameters
# TBD

success=0

# Set variables and save context
image_name="${1}"
extract_type=container
image_folder="$(basename ${image_name} | sed 's/:/--/').${extract_type}"
image_tar="${image_folder}".tar

#printf "image_name: ${image_name}\n"
#printf "image_folder: ${image_folder}\n"
#printf "image_tar: ${image_tar}\n"

# Check if folder exists; if it does, query user and remove it
# TBD - query user before continuing
if [ -d "${image_folder}" ]; then
    print_colored "${COLOR_YELLOW}" "Clearing old folder..."
    rm -rf "${image_folder}"
fi

# Create image folder
mkdir -p ${image_folder}

if is_sha256 "${image_name}"; then
      print_colored "${COLOR_BLUE}" "Image name is a sha256 hash"
    else
    # Check for the docker image and download if needed
    if [ -z "$(ctr image ls -q ${image_name} 2> /dev/null)" ]; then
      print_colored "${COLOR_BLUE}" "Pulling image ${image_name}"
      ctr image pull "${image_name}"
      if [ $? -ne 0 ]; then
        print_colored "${COLOR_RED}" "Could not pull docker image; exiting"
        rm -rf "${image_folder}"
        exit $?
      fi
    fi
fi

# start docker image and container in background; captute the new container ID
print_colored "${COLOR_BLUE}" "Starting container for image ${image_name}"
use_rm_flag=true
if [[ "${CTR_BIN}" == "nerdctl" ]]; then
  # nerdctl disallows -i with -d; run detached without -i and clean up manually
  run_flags=(-d)
  use_rm_flag=false
else
  run_flags=(-d -i --rm)
fi

# Try with entrypoint sh first
run_cmd=("${CTR_BIN}" "${CTR_ARGS[@]}" run "${run_flags[@]}" --entrypoint "sh" "${image_name}")
print_colored "${COLOR_BLUE}" "Run command: ${run_cmd[*]}"
if ! container_id=$("${run_cmd[@]}"); then
    # Fallback: default entrypoint
    run_cmd=("${CTR_BIN}" "${CTR_ARGS[@]}" run "${run_flags[@]}" "${image_name}")
    print_colored "${COLOR_BLUE}" "Fallback run command: ${run_cmd[*]}"
    if ! container_id=$("${run_cmd[@]}"); then
        print_colored "${COLOR_RED}" "Container could not be started; exiting"
        rm -rf "${image_folder}"
        exit $?
    fi
fi

print_colored "${COLOR_GREEN}" "Container ID: $container_id"

# Export the file system to a tar file
print_colored "${COLOR_BLUE}" "Writing filesystem to ${image_tar}"
ctr export --output="${image_tar}" ${container_id}
if [ $? -ne 0 ] 
then
    print_colored "${COLOR_RED}" "Export failed; exiting"
    rm -rf "${image_folder}"
    exit $?
fi

# Stop the container; no cleanup needed since we used the --rm flag
print_colored "${COLOR_BLUE}" "Stopping container ${container_id}"
ctr stop $container_id
if [ $? -ne 0 ] 
then
    print_colored "${COLOR_YELLOW}" "Error stopping the conatainer; continuing anyway"
fi

# If we could not use --rm (e.g., nerdctl), clean up the container now
if [[ "${use_rm_flag}" == "false" ]]; then
  ctr rm -f "$container_id" >/dev/null 2>&1
fi

# Extract the tar file (tolerate minor tar warnings)
print_colored "${COLOR_BLUE}" "Extracting image to disk..."
tar_status=0
tar -xpf "${image_tar}" --exclude='dev/*' -C "${image_folder}" || tar_status=$?
if [ ${tar_status} -ne 0 ]; then
    print_colored "${COLOR_YELLOW}" "tar reported warnings/errors (exit ${tar_status}) while extracting ${image_tar}. See messages above."
else
    print_colored "${COLOR_GREEN}" "Extracted container filesystem for ${container_id}"
fi

# Final assessment: success if tar and earlier steps completed
if [ ${tar_status} -eq 0 ]; then
  print_colored "${COLOR_GREEN}" "Container extract completed successfully: ${image_folder}"
  exit 0
else
  print_colored "${COLOR_YELLOW}" "Container extract completed with warnings/errors; see messages above."
  exit ${tar_status}
fi
