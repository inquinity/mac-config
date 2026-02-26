#!/bin/zsh
# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.0.0
#
# Runtime support:
# - dockerd: local docker source supported via syft docker:<image>
# - containerd/nerdctl: local images exported to docker-archive tar for syft scan
# - tar input: supported via syft docker-archive:<tar>

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

RUNTIME_BIN=""
RUNTIME_NERDCTL_NS="${NERDCTL_NAMESPACE:-default}"

runtime_image_inspect() {
    local image_ref="$1"
    if [[ "${RUNTIME_BIN}" == "nerdctl" ]]; then
        command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" image inspect "${image_ref}" >/dev/null 2>&1
    else
        command docker image inspect "${image_ref}" >/dev/null 2>&1
    fi
}

runtime_image_save() {
    local image_ref="$1"
    local out_file="$2"
    if [[ "${RUNTIME_BIN}" == "nerdctl" ]]; then
        command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" image save "${image_ref}" -o "${out_file}"
    else
        command docker image save "${image_ref}" -o "${out_file}"
    fi
}

detect_local_runtime_for_image() {
    local image_ref="$1"

    if command -v docker >/dev/null 2>&1 && command docker image inspect "${image_ref}" >/dev/null 2>&1; then
        RUNTIME_BIN="docker"
        return 0
    fi

    if command -v nerdctl >/dev/null 2>&1 && command nerdctl --namespace "${RUNTIME_NERDCTL_NS}" image inspect "${image_ref}" >/dev/null 2>&1; then
        RUNTIME_BIN="nerdctl"
        return 0
    fi

    if command -v nerdctl >/dev/null 2>&1 && command nerdctl image inspect "${image_ref}" >/dev/null 2>&1; then
        RUNTIME_BIN="nerdctl"
        return 0
    fi

    return 1
}

# Parse arguments
debug_mode=false
image_url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [OPTIONS] IMAGE_OR_TAR"
            print_colored "$COLOR_YELLOW" ""
            print_colored "$COLOR_YELLOW" "Options:"
            print_colored "$COLOR_YELLOW" "  --debug  Show CLI commands before execution"
            print_colored "$COLOR_YELLOW" ""
            print_colored "$COLOR_YELLOW" "Example:"
            print_colored "$COLOR_YELLOW" "  $(basename "$0") edgecore.optum.com/glb-docker-uhg-loc/uhg-goldenimages/external-dns:latest"
            print_colored "$COLOR_YELLOW" "  $(basename "$0") ./airflow--2-latest.image.tar"
            exit 0
            ;;
        --debug)
            debug_mode=true
            shift
            ;;
        -*)
            print_colored "$COLOR_RED" "Error: Unknown option '$1'"
            exit 1
            ;;
        *)
            image_url="$1"
            shift
            ;;
    esac
done

if [[ -z "$image_url" ]]; then
    print_colored "$COLOR_RED" "Error: IMAGE_OR_TAR is required"
    exit 1
fi

for tool in syft jq base64; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print_colored "$COLOR_RED" "Error: ${tool} is not installed."
        exit 1
    fi
done

sbom_file="$(mktemp "${TMPDIR:-/tmp}/sbom-XXXXXX.json")"
image_archive=""
trap 'rm -f "${sbom_file}" "${image_archive}"' EXIT

syft_source="registry:${image_url}"
is_tar_input=false
if [[ -f "${image_url}" ]]; then
    case "${image_url}" in
        *.tar|*.tar.gz|*.tgz)
            is_tar_input=true
            ;;
    esac
fi

if [[ "${is_tar_input}" == "true" ]]; then
    syft_source="docker-archive:${image_url}"
    print_colored "$COLOR_YELLOW" "Using docker-archive tar source: ${image_url}"
elif detect_local_runtime_for_image "${image_url}"; then
    if [[ "${RUNTIME_BIN}" == "docker" ]]; then
        syft_source="docker:${image_url}"
        print_colored "$COLOR_YELLOW" "Using local image from docker daemon."
    else
        image_archive="$(mktemp "${TMPDIR:-/tmp}/get-main-package-XXXXXX.tar")"
        if [[ "$debug_mode" == true ]]; then
            print_colored "$COLOR_CYAN" "$ nerdctl --namespace ${RUNTIME_NERDCTL_NS} image save ${image_url} -o ${image_archive}"
        fi
        if runtime_image_save "${image_url}" "${image_archive}" >/dev/null 2>&1; then
            syft_source="docker-archive:${image_archive}"
            print_colored "$COLOR_YELLOW" "Using local image from nerdctl namespace ${RUNTIME_NERDCTL_NS}."
        else
            print_colored "$COLOR_YELLOW" "Warning: failed to export local image; falling back to registry source."
            rm -f "${image_archive}"
            image_archive=""
        fi
    fi
fi

# Generate SBOM
print_colored "$COLOR_GREEN" "Generating SBOM for image: $image_url"
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ syft scan ${syft_source} -o syft-json > ${sbom_file}"
fi
syft scan "${syft_source}" -o syft-json > "$sbom_file" 2>/dev/null
if [[ $? -ne 0 ]]; then
    print_colored "$COLOR_RED" "Error: Failed to generate SBOM for image"
    exit 1
fi

# Extract main package name
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ jq -r '.source.metadata.labels[\"dev.chainguard.package.main\"]' $sbom_file"
fi
main_pkg=$(jq -r '.source.metadata.labels["dev.chainguard.package.main"] // empty' "$sbom_file")
if [[ -z "$main_pkg" ]]; then
    print_colored "$COLOR_RED" "Error: Could not find main package label in image"
    exit 1
fi

# Extract version
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ jq -r '.artifacts[] | select(.name==\"\${main_pkg}\" or (.name|startswith(\"\${main_pkg}-\")) or (.name|startswith(\"\${main_pkg}:\"))) | .version' $sbom_file | head -n1"
fi
version=$(jq -r --arg pkg "${main_pkg}" '
  .artifacts[]
  | select(.name==$pkg or (.name|startswith($pkg+"-")) or (.name|startswith($pkg+":")))
  | .version
' "$sbom_file" | head -n1)
if [[ -z "$version" ]]; then
    # last resort: show nearby package names to aid debugging
    print_colored "$COLOR_RED" "Error: Could not find version for package '$main_pkg'"
    nearby=$(jq -r --arg pkg "${main_pkg}" '.artifacts[].name | select(contains($pkg))' "$sbom_file" | head -n5)
    if [[ -n "$nearby" ]]; then
      print_colored "$COLOR_YELLOW" "Packages containing '${main_pkg}' seen in SBOM:"
      print_colored "$COLOR_YELLOW" "$nearby"
    fi
    exit 1
fi

# Extract Chainguard base image build date
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ jq -r '.source.metadata.config' $sbom_file | base64 -d | jq -r '.history[0].created'"
fi
image_date=$(jq -r '.source.metadata.config' "$sbom_file" | base64 -d | jq -r '.history[0].created // empty')
if [[ -z "$image_date" ]]; then
    image_date=$(jq -r '.source.metadata.labels["golden.container.image.build.release"] // empty' "$sbom_file")
    if [[ -n "$image_date" ]]; then
        image_date="${image_date} (golden image date)"
    fi
fi

# Print results
printf "\n"
print_colored "$COLOR_MAGENTA" "IMAGE: $image_url"
print_colored "$COLOR_MAGENTA" "Image date: $image_date"
print_colored "$COLOR_MAGENTA" "Main Package: $main_pkg"
print_colored "$COLOR_MAGENTA" "Version: $version"
printf "\n"
