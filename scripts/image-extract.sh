#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.1.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/image-extract.sh

# Requirements:
# * Container runtime: nerdctl (Rancher Desktop, default namespace) or docker
# * jq formatter - https://jqlang.github.io/jq/

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

overall_status=0
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

jq_format_file() {
  local the_file="$1"
  local tmp_file="jq-temp.json"

  if [ -z "${the_file}" ] || [ ! -f "${the_file}" ]; then
    return 0
  fi

  if file --brief "${the_file}" | grep -q "JSON"; then
    print_colored "${COLOR_BLUE}" "Formatting ${the_file} as JSON"
    jq "." "${the_file}" > "${tmp_file}" && cp -f "${tmp_file}" "${the_file}" && rm -f "${tmp_file}"
  fi
}

is_sha256() {
  if [ -z "$1" ]; then
    return 1
  fi
  [[ "$1" =~ ^[a-f0-9]{12}$|^[a-f0-9]{64}$ ]]
}

for tool in jq tar file; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    print_colored "${COLOR_RED}" "Error: ${tool} is not installed."
    exit 1
  fi
done

image_name="${1}"
if [ -z "${image_name}" ] || [[ "${image_name}" == "-h" ]] || [[ "${image_name}" == "--help" ]]; then
  usage
  exit 1
fi

detect_runtime_for_image "${image_name}" || exit 1

pushd . >/dev/null
extract_type="image"
image_folder="$(basename "${image_name}" | sed 's/:/--/').${extract_type}"
image_tar="${image_folder}.tar"
blobs_path="blobs/sha256"

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
    popd >/dev/null
    exit 1
  fi
fi

print_colored "${COLOR_BLUE}" "Exporting image ..."
if ! runtime_cmd image save "${image_name}" -o "${image_tar}"; then
  print_colored "${COLOR_RED}" "Save failed; exiting"
  rm -rf "${image_folder}"
  popd >/dev/null
  exit 1
fi

print_colored "${COLOR_BLUE}" "Extracting image ..."
tar_status=0
tar -xpf "${image_tar}" --exclude='dev/*' -C "${image_folder}" >/dev/null 2>&1 || tar_status=$?
if [ ${tar_status} -ne 0 ]; then
  overall_status=${tar_status}
fi

cd "${image_folder}" || {
  print_colored "${COLOR_RED}" "Failed to enter ${image_folder}"
  popd >/dev/null
  exit 1
}

config_file="$(jq --raw-output '.[0].Config' manifest.json 2>/dev/null)"
if [ -n "${config_file}" ] && [ "${config_file}" != "null" ] && [ -f "${config_file}" ]; then
  mv "${config_file}" "${config_file}-config.json"
fi

for filename in *; do
  jq_format_file "${filename}"
done

if [ -d "${blobs_path}" ]; then
  for filename in "${blobs_path}"/*; do
    [ -f "${filename}" ] || continue
    jq_format_file "${filename}"
  done
fi

layer_counter=0
while IFS= read -r layer_name; do
  layer_counter=$((layer_counter + 1))
  layer_file="${layer_name}"
  layer_suffix="${layer_name#${blobs_path}/}"
  layer_folder="${blobs_path}/$(printf '%02d' "${layer_counter}")-${layer_suffix}"
  tar_file="${layer_name}.tar"

  print_colored "${COLOR_BLUE}" "Found layer ${layer_counter}: ${layer_name}"
  if [ -f "${layer_file}" ]; then
    mv "${layer_file}" "${tar_file}"
    mkdir -p "${layer_folder}"
    tar -xpf "${tar_file}" --exclude='dev/*' -C "${layer_folder}" >/dev/null 2>&1 || overall_status=$?
  else
    print_colored "${COLOR_YELLOW}" "Skipping duplicate layer blob"
  fi
done < <(jq --raw-output '.[0].Layers[]' manifest.json)

history_out="${image_folder}_history.txt"
config_ref="$(jq --raw-output '.[0].Config' manifest.json 2>/dev/null)"
config_json="${config_ref}-config.json"
print_colored "${COLOR_BLUE}" "Writing layer history to ${history_out}"

if [ -f "${config_json}" ]; then
  history_tsv="$(jq -r '
    .history as $h
    | .rootfs.diff_ids as $d
    | [range(0; ($h|length))] as $idxs
    | $idxs
    | map(
        {
          idx: (. + 1),
          created: ($h[.]?.created // ""),
          created_by: ($h[.]?.created_by // ""),
          size: ($h[.]?.size // 0),
          diff_id: ($d[.] // "")
        }
      )
    | (["#","DIFF_ID","CREATED","SIZE","CREATED_BY"] | @tsv),
      ( .[] | [
          (.idx|tostring),
          ((.diff_id|sub("^sha256:";""))[0:12]),
          (.created),
          (.size|tostring),
          (.created_by|gsub("\n";" ")|gsub("\t";" "))
        ] | @tsv )
  ' "${config_json}" 2>/dev/null)"

  if [ -n "${history_tsv}" ]; then
    if command -v column >/dev/null 2>&1; then
      printf "%s\n" "${history_tsv}" | column -t -s $'\t' > "${history_out}"
    else
      printf "%s\n" "${history_tsv}" > "${history_out}"
    fi
  fi
fi

popd >/dev/null

if [ ${overall_status} -eq 0 ]; then
  print_colored "${COLOR_GREEN}" "Image extract completed successfully: ${image_folder}"
else
  print_colored "${COLOR_YELLOW}" "Image extract completed with warnings/errors; see messages above."
fi
