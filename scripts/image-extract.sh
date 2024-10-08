#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.2.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/image-extract.sh

# Requirements:
# * Docker Desktop, or docker cli
# * jq formatter - https://jqlang.github.io/jq/

# Format a JSON file; tests file existence and type, so it is safe to use on any filename
jq_format_file()
{
    # Validate parameters
    if [ -z "$1" ]; then
	  return 0
    fi

    tmp_file=jq-temp.json
    the_file="${1}"

    # Check if the file is JSON; if it is, format it to a temp file and then replace the original with the formatted file; clean up afterwards
    if file --brief "${the_file}" | grep -q "JSON"; then
	  echo Formatting ${the_file} as JSON
	  jq "." "${the_file}" > "${tmp_file}" && cp -f "${tmp_file}" "${the_file}" && rm "${tmp_file}"
    fi
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

# Validate parameters
# TBD

# Set variables and save context
pushd .
image_name="${1}"
extract_type=image
image_folder="$(basename ${image_name} | sed 's/:/--/').${extract_type}"
image_tar="${image_folder}".tar
blobs_path="blobs/sha256/"
blobs_path_len=${#blobs_path}

echo image_name: ${image_name}
echo image_folder: ${image_folder}
echo image_tar: ${image_tar}
echo tmp_file: ${tmp_file}

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

# Display layer info (visual nicety)
docker image history ${image_name}
docker image history --no-trunc --format 'table {{.ID}}\t{{printf "%.10s" .CreatedAt}}\t{{.Size}}\t{{.Comment}}\n{{.CreatedBy}}\n' "${image_name}" > "${image_folder}/${image_folder}"_history.txt

# Export the image
echo Exporting image ...
docker image save "${image_name}" -o "${image_tar}"
if [ $? -ne 0 ] 
then
    echo Save failed; exiting
    rm -rf "${image_folder}"
    exit $?
fi

# Extract image
echo Extracting image ...
tar -xvf "${image_tar}" -C "${image_folder}"
if [ $? -ne 0 ] 
then
    echo Error unarchive tar file: ${image_tar}
    exit $?
fi

cd "${image_folder}"

# Get the config file and rename it
config_file="$(jq --raw-output ".[0].Config" manifest.json)"
echo config_file: ${config_file}
mv "${config_file}" "${config_file}-config.json"


# Format JSON files for easier reading
for filename in *; do
    jq_format_file "${filename}"
done

# Formatting JSON files in blob path
for filename in ${blobs_path}*; do
    jq_format_file "${filename}"
done

# Determine which sha files are tars - Rename them; extract them; add layer number to folders
layer_counter=0
jq --raw-output ".[0].Layers[]" manifest.json | \
    while read layer_name
    do
	(( layer_counter++ ))
	layer_file="${layer_name}"
	layer_folder="${blobs_path}$(printf '%02d' $layer_counter)-${layer_name:(${#blobs_path})}"
	tar_file="${layer_name}".tar
	echo Found layer $layer_counter: ${layer_name}
	echo $layer_folder
	if [ -f "${layer_file}" ]; then
	    mv "${layer_file}" "${tar_file}"
	    echo Extracting ${tar_file}...
	    mkdir -p "${layer_folder}"
	    tar -xvf "${tar_file}" -C "${layer_folder}"
	else
	    echo Skipping duplicate layer blob
	fi
    done


# Restore origial context
popd
