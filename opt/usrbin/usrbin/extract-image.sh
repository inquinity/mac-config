#! zsh

# Format a JSON file; tests file existence and type, so it is safe to use on any filename
jq_format_file()
{
    # Validate paramters
    if [ -z "$1" ]; then
	return 0
    fi

    tmp_file=jq-temp.json
    the_file="${1}"

    # Check if the file is JSON; if it is, format it to a temp file and then replace the original with the formatted file; clean up afterwards
    if file --brief "${the_file}" | grep -q "JSON"; then
	echo Formatting ${the_file} as JSON
	jq "." "${the_file}" > "${tmp_file}" && cp "${tmp_file}" "${the_file}" && rm "${tmp_file}"
    fi
}

# Validate parameters
# TBD

# Set variables and save context
pushd .
image_name="${1}"
image_folder="$(basename ${image_name} | sed 's/:/--/')"
image_tar="${image_folder}".tar
blobs_path="blobs/sha256/"
blobs_path_len=${#blobs_path}

#echo image_name: ${image_name}
#echo image_folder: ${image_folder}
#echo image_tar: ${image_tar}
#echo tmp_file: ${tmp_file}

# Check if folder exists; if it does, query user and remove it
# TBD - query user before continuing
if [ -d "${image_folder}" ]; then
    echo Clearing old folder...
    rm -rf "${image_folder}"
fi

# Create image folder
mkdir -p ${image_folder}

# Clear display
#read -s -k '?Press enter to continue.'
#clear

# Check for the docker image and download if needed
if [ -z "$(docker images -q ${image_name} 2> /dev/null)" ]; then
    echo Pulling image ${image_name}
    docker pull "${image_name}"
fi

# Display layer info (visual nicety)
docker history ${image_name}
docker history --no-trunc "${image_name}" > "${image_folder}/${image_folder}"_history.txt

# Export the image
echo Exporting image ...
docker save "${image_name}" -o "${image_tar}"

# Extract image
echo Extracting image ...
tar -xvf "${image_tar}" -C "${image_folder}"
chdir "${image_folder}"

# Get the config file and rename it
config_file="$(jq --raw-output ".[0].Config" manifest.json)"
echo config_file: ${config_file}
mv "${config_file}" "config-${config_file}.json"

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
	layer_folder="${blobs_path}$(printf '%02d' layer_counter)-${layer_name:(${#blobs_path})}"
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
