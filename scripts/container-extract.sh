#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.1.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/container-extract.sh

# Requirements:
# * Docker Desktop, or docker cli

# Validate parameters
# TBD

# Set variables and save context
image_name="${1}"
extract_type=container
image_folder="$(basename ${image_name} | sed 's/:/--/').${extract_type}"
image_tar="${image_folder}".tar

#echo image_name: ${image_name}
#echo image_folder: ${image_folder}
#echo image_tar: ${image_tar}

# Check if folder exists; if it does, query user and remove it
# TBD - query user before continuing
if [ -d "${image_folder}" ]; then
    echo Clearing old folder...
    rm -rf "${image_folder}"
fi

# Create image folder
mkdir -p ${image_folder}

# start docker image and container in background; captute the new container ID
echo Starting container for image ${image_name}
container_id=$(docker run --rm --interactive --detach --entrypoint="sh" "${image_name}" )
echo Container ID: $container_id

# Export the file system to a tar file
echo Writing filesystem to ${image_tar}
docker export --output="${image_tar}" ${container_id}

# Stop the container; no cleanup needed since we used the --rm flag
echo Stopping container ${contained_id}
docker stop $container_id

# Extract the tar file
echo Extracting image to disk...
tar -xvf "${image_tar}" -C "${image_folder}"
