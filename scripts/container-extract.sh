#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.2.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/container-extract.sh

# Requirements:
# * Docker Desktop, or docker cli

is_sha256()
{
    # Validate parameters
    if [ -z "$1" ]; then
      return 0
    fi

    [[ "$1" =~ ^[a-f0-9]{12}$|^[a-f0-9]{64}$ ]]
    return $?
}

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

if is_sha256 "${image_name}"; then
      echo "Image name is a sha256 hash"
    else
    # Check for the docker image and download if needed
    if [ -z "$(docker image ls -q ${image_name} 2> /dev/null)" ]; then
      echo Pulling image ${image_name}
      docker image pull "${image_name}"
      if [ $? -ne 0 ]; then
	    echo Could not pull docker image; exiting
	    rm -rf "${image_folder}"
	    exit $?
      fi
    fi
fi

# start docker image and container in background; captute the new container ID
echo Starting container for image ${image_name}
container_id=$(docker container run --rm --interactive --detach --entrypoint "sh" "${image_name}" )
if [ $? -ne 0 ] 
then
    container_id=$(docker container run --rm --interactive --detach "${image_name}" )
    if [ $? -ne 0 ]
    then
        echo Container could not be started; exiting
	rm -rf "${image_folder}"
	exit $?
    fi
fi

echo Container ID: $container_id

# Export the file system to a tar file
echo Writing filesystem to ${image_tar}
docker container export --output="${image_tar}" ${container_id}
if [ $? -ne 0 ] 
then
    echo Export failed; exiting
    exit $?
fi

# Stop the container; no cleanup needed since we used the --rm flag
echo Stopping container ${contained_id}
docker container stop $container_id
if [ $? -ne 0 ] 
then
    echo Error stopping the conatainer; continuing anyway
fi

# Extract the tar file
echo Extracting image to disk...
tar -xvf "${image_tar}" -C "${image_folder}"
if [ $? -ne 0 ] 
then
    echo Error unarchive tar file: ${image_tar}
    exit $?
else 
    echo Container ID: $container_id
fi

exit 0
