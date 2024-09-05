#! /bin/bash

video_name="${1%.*}"
source_file="${1}"
destination_file="${video_name}".mp4

# Check if source_file exists
if [ ! -f "${source_file}" ]; then
  echo "Error: Source file '${source_file}' does not exist."
  exit 1
fi

echo Converting "${source_file}" to "${destination_file}"
ffmpeg -i "${source_file}" -vcodec h264 -acodec aac "${destination_file}"
