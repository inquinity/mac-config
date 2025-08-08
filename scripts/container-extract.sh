#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.2.5
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/container-extract.sh

# Requirements:
# * Docker Desktop, or docker cli

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

is_sha256()
{
    # Validate parameters
    if [ -z "$1" ]; then
      return 0
    fi

    [[ "$1" =~ ^[a-f0-9]{12}$|^[a-f0-9]{64}$ ]]
    return $?
}

# Validate required tool: docker cli
if ! command -v docker &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: docker cli is not installed. Please install docker cli to use this script." >&2
  exit 1
fi

# Validate required tool: jq
if ! command -v jq &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: jq is not installed. Please install jq to use this script." >&2
  exit 1
fi

# Validate parameters
# TBD

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
    if [ -z "$(docker image ls -q ${image_name} 2> /dev/null)" ]; then
      print_colored "${COLOR_BLUE}" "Pulling image ${image_name}"
      docker image pull "${image_name}"
      if [ $? -ne 0 ]; then
	    print_colored "${COLOR_RED}" "Could not pull docker image; exiting"
	    rm -rf "${image_folder}"
	    exit $?
      fi
    fi
fi

# start docker image and container in background; captute the new container ID
print_colored "${COLOR_BLUE}" "Starting container for image ${image_name}"
container_id=$(docker container run --rm --interactive --detach --entrypoint "sh" "${image_name}" )
if [ $? -ne 0 ] 
then
    container_id=$(docker container run --rm --interactive --detach "${image_name}" )
    if [ $? -ne 0 ]
    then
        print_colored "${COLOR_RED}" "Container could not be started; exiting"
	rm -rf "${image_folder}"
	exit $?
    fi
fi

print_colored "${COLOR_GREEN}" "Container ID: $container_id"

# Export the file system to a tar file
print_colored "${COLOR_BLUE}" "Writing filesystem to ${image_tar}"
docker container export --output="${image_tar}" ${container_id}
if [ $? -ne 0 ] 
then
    print_colored "${COLOR_RED}" "Export failed; exiting"
    exit $?
fi

# Stop the container; no cleanup needed since we used the --rm flag
print_colored "${COLOR_BLUE}" "Stopping container ${contained_id}"
docker container stop $container_id
if [ $? -ne 0 ] 
then
    print_colored "${COLOR_YELLOW}" "Error stopping the conatainer; continuing anyway"
fi

# Extract the tar file
print_colored "${COLOR_BLUE}" "Extracting image to disk..."
tar -xvf "${image_tar}" -C "${image_folder}"
if [ $? -ne 0 ] 
then
    print_colored "${COLOR_RED}" "Error unarchive tar file: ${image_tar}"
    exit $?
else 
    print_colored "${COLOR_GREEN}" "Container ID: $container_id"
fi

exit 0
