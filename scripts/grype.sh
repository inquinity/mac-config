#!/bin/zsh

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 0.2.0
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/grype-all.sh
#
# Purpose:
# Run grype against a Docker image with --scope all-layers, then join each
# vulnerability to the layer digest and the Dockerfile instruction (CreatedBy)
# that introduced that layer.
#
# Requirements:
# 1. A container runtime: nerdctl (Rancher Desktop, default namespace assumed) or docker
# 2. grype installed
# 3. jq installed

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

# -----------------------
# Container runtime detection (prefer nerdctl)
# -----------------------
typeset -g CONTAINER_BIN=""
typeset -a CONTAINER_ARGS
CONTAINER_ARGS=()
NERDCTL_NS=${NERDCTL_NAMESPACE:-default}

detect_container_runtime() {
  if command -v nerdctl >/dev/null 2>&1 && nerdctl --namespace "${NERDCTL_NS}" info >/dev/null 2>&1; then
    CONTAINER_BIN="nerdctl"
    CONTAINER_ARGS=(--namespace "${NERDCTL_NS}")
    print_colored "${COLOR_YELLOW}" "Using nerdctl (namespace ${NERDCTL_NS})."
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    CONTAINER_BIN="docker"
    CONTAINER_ARGS=()
    print_colored "${COLOR_YELLOW}" "Using docker daemon."
    return 0
  fi

  print_colored "${COLOR_RED}" "No container runtime daemon reachable (tried nerdctl namespace '${NERDCTL_NS}' then docker)."
  return 1
}

ctr() {
  "${CONTAINER_BIN}" "${CONTAINER_ARGS[@]}" "$@"
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [grype-args...] <target>
  $(basename "$0") --layers [--keep-files] <image-name>

Example:
  # Default behavior: run grype with --by-cve added
  $(basename "$0") alpine:3.20

  # Layer-enriched behavior
  $(basename "$0") --layers my-registry.example.com/team/image:tag
  $(basename "$0") --layers --keep-files my-registry.example.com/team/image:tag

Notes:
  - Bypass aliases/functions and run the real grype with: command grype ...
EOF
}

set -o pipefail

# -----------------------
# Mode selection
# -----------------------

want_layers=false
args=()
for a in "$@"; do
  if [[ "$a" == "--layers" ]]; then
    want_layers=true
  else
    args+=("$a")
  fi
done

# Detect runtime early
detect_container_runtime || exit 1

# Wrapper mode (default): just run grype --by-cve with original args.
if [[ "${want_layers}" != "true" ]]; then
  if ! command -v grype &> /dev/null; then
    print_colored "${COLOR_RED}" "Error: grype is not installed. Please install grype to use this script." >&2
    exit 1
  fi

  # Avoid injecting --by-cve for grype subcommands where it can break behavior.
  if [[ "${#args[@]}" -gt 0 ]]; then
    case "${args[1]}" in
      version|help|db|completion)
        exec command grype "${args[@]}"
        ;;
    esac
  fi

  exec command grype --by-cve "${args[@]}"
fi

# -----------------------
# Validate required tools (layers mode)
# -----------------------

if ! command -v grype &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: grype is not installed. Please install grype to use this script." >&2
  exit 1
fi

if ! command -v jq &> /dev/null; then
  print_colored "${COLOR_RED}" "Error: jq is not installed. Please install jq to use this script." >&2
  exit 1
fi

# -----------------------
# Validate parameters
# -----------------------

# Reset positional args to the layers-mode args (i.e., with --layers removed)
set -- "${args[@]}"

keep_files=false
image_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-files)
      keep_files=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      print_colored "${COLOR_RED}" "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      image_name="$1"
      shift
      ;;
  esac
done

if [[ -z "${image_name}" ]]; then
  print_colored "${COLOR_YELLOW}" "Missing image name."
  usage
  exit 1
fi
username=${USER}
datestr="$(date +%Y-%m-%d)"
basestr=$(echo "$(basename "${image_name}")" | sed -r "s/:/--/g")

scan_results=""
scan_layer_map=""
scan_grype_json=""
if [[ "${keep_files}" == "true" ]]; then
  scan_results="${datestr}_${basestr}_grype_layers.txt"
  scan_layer_map="${datestr}_${basestr}_layer_map.txt"
  scan_grype_json="${datestr}_${basestr}_grype.json"
fi

# Validate image exists locally
ctr image inspect "${image_name}" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  print_colored "${COLOR_RED}" "Requested image \"${image_name}\" does not exist locally (inspect failed)."
  exit 1
fi

# Clean up any previous scan results (only if we are persisting files)
if [[ "${keep_files}" == "true" ]]; then
  if [ -f "${scan_results}" ] ; then
    rm "${scan_results}"
  fi

  if [ -f "${scan_layer_map}" ] ; then
    rm "${scan_layer_map}"
  fi

  if [ -f "${scan_grype_json}" ] ; then
    rm "${scan_grype_json}"
  fi
fi

# -----------------------
# Build layer → command map
# -----------------------
print_colored "${COLOR_YELLOW}" "Collecting layer metadata for ${image_name}..."

# Build a reliable mapping of layer digest/diff_id → Dockerfile created_by by reading
# the image's config history (created_by), manifest layer list (compressed digests),
# and rootfs diff_ids (uncompressed digests). Grype typically reports layerID as the
# diff_id, so we index by diff_id to avoid mismatches.
#
# This is done entirely in-memory (no temp files) by streaming `image save`
# into `tar -xOf -`.
manifest_json="$(ctr image save "${image_name}" | tar -xOf - manifest.json 2>/dev/null)"
if [[ -z "${manifest_json}" ]]; then
  print_colored "${COLOR_RED}" "Error: failed to read manifest.json from docker image save stream."
  exit 1
fi

config_path="$(print -r -- "${manifest_json}" | jq -r '.[0].Config' 2>/dev/null)"
if [[ -z "${config_path}" || "${config_path}" == "null" ]]; then
  print_colored "${COLOR_RED}" "Error: failed to locate config path in manifest.json."
  exit 1
fi

config_json="$(ctr image save "${image_name}" | tar -xOf - "${config_path}" 2>/dev/null)"
if [[ -z "${config_json}" ]]; then
  print_colored "${COLOR_RED}" "Error: failed to read image config JSON (${config_path}) from docker image save stream."
  exit 1
fi

layers_len="$(print -r -- "${manifest_json}" | jq -r '.[0].Layers | length' 2>/dev/null)"
hist_len="$(print -r -- "${config_json}" | jq -r '.history | map(select((.empty_layer // false) | not)) | length' 2>/dev/null)"
diff_len="$(print -r -- "${config_json}" | jq -r '.rootfs.diff_ids | length' 2>/dev/null)"
if [[ -n "${layers_len}" && -n "${hist_len}" && "${layers_len}" != "${hist_len}" ]]; then
    print_colored "${COLOR_YELLOW}" "WARN: layer/history length mismatch: layers=${layers_len}, history(non-empty)=${hist_len}. Mapping will align by index from start."
fi
if [[ -n "${diff_len}" && -n "${hist_len}" && "${diff_len}" != "${hist_len}" ]]; then
    print_colored "${COLOR_YELLOW}" "WARN: diff_ids/history length mismatch: diff_ids=${diff_len}, history(non-empty)=${hist_len}. Mapping will use the shortest length."
fi

typeset -a layers
typeset -a created_by
typeset -a diff_ids
layers=( ${(f)"$(print -r -- "${manifest_json}" | jq -r '.[0].Layers[]' 2>/dev/null)"} )
created_by=( ${(f)"$(print -r -- "${config_json}" | jq -r '.history[] | select((.empty_layer // false) | not) | (.created_by // "")' 2>/dev/null)"} )
diff_ids=( ${(f)"$(print -r -- "${config_json}" | jq -r '.rootfs.diff_ids[]' 2>/dev/null)"} )

n_hist=${#created_by[@]}
n_diff=${#diff_ids[@]}
n_map=$n_hist
if (( n_diff < n_map )); then n_map=${n_diff}; fi

typeset -A LAYER_CREATED_BY
typeset -A LAYER_INDEX

for (( i=1; i<=n_map; i++ )); do
  diff="${diff_ids[$i]}"
  diff="${diff#sha256:}"

  cmd="${created_by[$i]}"
  # Normalize the command similarly to docker history readability.
  cmd="${cmd#/bin/sh -c }"
  cmd="${cmd#\#(nop) }"
  cmd="${cmd//$'\n'/ }"
  cmd="${cmd//$'\t'/ }"
  cmd="${cmd//  / }"

  if [[ -n "${diff}" ]]; then
    LAYER_CREATED_BY["${diff}"]="${cmd}"
    LAYER_INDEX["${diff}"]="${i}"
  fi
done

if [[ "${keep_files}" == "true" ]]; then
  # Save a simple TSV map: digest<TAB>layer_index<TAB>created_by
  : > "${scan_layer_map}"
  for k in ${(k)LAYER_INDEX}; do
    printf "%s\t%s\t%s\n" "$k" "${LAYER_INDEX[$k]}" "${LAYER_CREATED_BY[$k]}" >> "${scan_layer_map}"
  done
fi

# -----------------------
# Run grype and enrich with layer + command
# -----------------------
print_colored "${COLOR_YELLOW}" "Running grype scan on ${image_name} (scope: all-layers)..."

# Column headers for the enriched output
print_colored "${COLOR_BRIGHTYELLOW}" "LYR  PACKAGE                        VERSION              TYPE       SEVERITY CVE                LAYER_SHA     DOCKERFILE_COMMAND"
print_colored "${COLOR_BRIGHTYELLOW}" "--------------------------------------------------------------------------------------------------------------------------------------------"

# We will:
# 1. Run grype as JSON
# 2. Extract relevant fields and the full layer digest from .artifact.locations[0].layerID
# 3. Join to the layer_map_file to pull in the Dockerfile CreatedBy line
# 4. Print a nicely formatted table to ${scan_results}

command grype "${image_name}" --by-cve --scope all-layers -o json 2> /dev/null \
  | ( if [[ "${keep_files}" == "true" ]]; then tee "${scan_grype_json}"; else cat; fi ) \
  | jq -r '
      .matches[]
      | .artifact as $a
      | .vulnerability as $v
      | (($a.locations // [])
          | map(.layerID // empty)
          | map(sub("^sha256:"; ""))
          | unique
        ) as $layers
      | if ($layers|length) == 0 then
          [
            $a.name,
            ($a.version // ""),
            ($a.type // ""),
            ($v.severity // ""),
            ($v.id // ""),
            "",
            ""
          ] | @tsv
        else
          $layers[] as $digest
          | [
              $a.name,
              ($a.version // ""),
              ($a.type // ""),
              ($v.severity // ""),
              ($v.id // ""),
              ($digest | sub("^sha256:";"") | .[0:12]),
              ($digest | sub("^sha256:";""))
            ] | @tsv
        end
    ' \
  | while IFS=$'\t' read -r pkg ver ptype sev cve short_digest full_digest; do
        idx="${LAYER_INDEX["${full_digest}"]}"
        cmd="${LAYER_CREATED_BY["${full_digest}"]}"

        if [[ -z "${full_digest}" ]]; then
            idx="-"
            cmd="(no layerID reported by grype for this match)"
            short_digest="-"
        elif [[ -z "${cmd}" ]]; then
          idx="${idx:-?}"
          cmd="(no matching image history entry for this layer diff_id)"
        fi

          printf "%-4s %-30s %-20s %-10s %-8s %-18s %-12s %s\n" \
            "${idx}" "${pkg}" "${ver}" "${ptype}" "${sev}" "${cve}" "${short_digest}" "${cmd}"
    done \
        | ( if [[ "${keep_files}" == "true" ]]; then tee "${scan_results}"; else cat; fi )

grype_exit_code=${pipestatus[1]}

# -----------------------
# Report results
# -----------------------

if [[ -z "${grype_exit_code}" || "${grype_exit_code}" -eq 0 ]]; then
    print_colored "${COLOR_GREEN}" "Grype scan completed successfully."

    if [[ "${keep_files}" == "true" ]]; then
      print_colored "${COLOR_GREEN}" "Results saved to ${scan_results}"
      print_colored "${COLOR_GREEN}" "Layer map saved to ${scan_layer_map}"
      print_colored "${COLOR_GREEN}" "Raw grype JSON saved to ${scan_grype_json}"
    fi
else
    print_colored "${COLOR_RED}" "grype failed with status ${grype_exit_code}"
    if [[ "${keep_files}" == "true" ]]; then
      print_colored "${COLOR_YELLOW}" "Partial or no results may have been written to ${scan_results}"
    fi
fi
