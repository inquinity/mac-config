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
debug_mode=false
image_url=""
sbom_file=""
image_archive=""
syft_error_file=""

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

show_help() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [OPTIONS] IMAGE_OR_TAR"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Options:"
    print_colored "$COLOR_YELLOW" "  --debug  Show CLI commands before execution"
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "Example:"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") edgecore.optum.com/glb-docker-uhg-loc/uhg-goldenimages/external-dns:latest"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") ./airflow--2-latest.image.tar"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
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
}

require_tools() {
    local tool
    for tool in syft jq base64; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            print_colored "$COLOR_RED" "Error: ${tool} is not installed."
            exit 1
        fi
    done
}

create_temp_path() {
    local prefix="$1"
    local tmp_path=""

    if tmp_path="$(mktemp -t "${prefix}")"; then
        printf '%s\n' "$tmp_path"
        return 0
    fi

    print_colored "$COLOR_RED" "Error: Failed to create temporary file for ${prefix}"
    exit 1
}

setup_temp_files() {
    sbom_file="$(create_temp_path "sbom")"
    syft_error_file="$(create_temp_path "syft-error")"
    image_archive=""
    trap 'rm -f "${sbom_file}" "${syft_error_file}" "${image_archive}"' EXIT
}

determine_syft_source() {
    local is_tar_input=false
    local syft_source="registry:${image_url}"

    if [[ -f "${image_url}" ]]; then
        case "${image_url}" in
            *.tar|*.tar.gz|*.tgz)
                is_tar_input=true
                ;;
        esac
    fi

    if [[ "${is_tar_input}" == "true" ]]; then
        print_colored "$COLOR_YELLOW" "Using docker-archive tar source: ${image_url}" >&2
        printf '%s\n' "docker-archive:${image_url}"
        return 0
    fi

    if detect_local_runtime_for_image "${image_url}"; then
        if [[ "${RUNTIME_BIN}" == "docker" ]]; then
            print_colored "$COLOR_YELLOW" "Using local image from docker daemon." >&2
            printf '%s\n' "docker:${image_url}"
            return 0
        fi

        image_archive="$(create_temp_path "get-main-package")"
        if [[ "$debug_mode" == true ]]; then
            print_colored "$COLOR_CYAN" "$ nerdctl --namespace ${RUNTIME_NERDCTL_NS} image save ${image_url} -o ${image_archive}" >&2
        fi
        if runtime_image_save "${image_url}" "${image_archive}" >/dev/null 2>&1; then
            print_colored "$COLOR_YELLOW" "Using local image from nerdctl namespace ${RUNTIME_NERDCTL_NS}." >&2
            printf '%s\n' "docker-archive:${image_archive}"
            return 0
        fi

        print_colored "$COLOR_YELLOW" "Warning: failed to export local image; falling back to registry source." >&2
        rm -f "${image_archive}"
        image_archive=""
    fi

    printf '%s\n' "${syft_source}"
}

generate_sbom() {
    local syft_source="$1"

    print_colored "$COLOR_GREEN" "Generating SBOM for image: $image_url"
    if [[ "$debug_mode" == true ]]; then
        print_colored "$COLOR_CYAN" "$ SYFT_CHECK_FOR_APP_UPDATE=false syft scan ${syft_source} -o syft-json > ${sbom_file}"
    fi

    if ! SYFT_CHECK_FOR_APP_UPDATE=false syft scan "${syft_source}" -o syft-json > "$sbom_file" 2> "$syft_error_file"; then
        print_colored "$COLOR_RED" "Error: Failed to generate SBOM for image"
        if [[ -s "$syft_error_file" ]]; then
            print_colored "$COLOR_YELLOW" "Syft output:"
            cat "$syft_error_file"
        fi
        if [[ "${syft_source}" == registry:* ]]; then
            if [[ -n "${DOCKER_CONFIG:-}" ]]; then
                print_colored "$COLOR_YELLOW" "Registry auth config expected at: ${DOCKER_CONFIG}/config.json"
            else
                print_colored "$COLOR_YELLOW" "DOCKER_CONFIG is not set. Syft registry scans may need a Docker auth config."
            fi
        fi
        exit 1
    fi
}

extract_main_package() {
    if [[ "$debug_mode" == true ]]; then
        print_colored "$COLOR_CYAN" "$ jq -r '.source.metadata.labels[\"dev.chainguard.package.main\"]' ${sbom_file}"
    fi

    jq -r '.source.metadata.labels["dev.chainguard.package.main"] // empty' "$sbom_file"
}

extract_package_version() {
    local main_pkg="$1"

    if [[ "$debug_mode" == true ]]; then
        print_colored "$COLOR_CYAN" "$ jq -r --arg pkg \"${main_pkg}\" '<filtered package query>' ${sbom_file}"
    fi

    jq -r --arg pkg "${main_pkg}" '
      def normalized_version:
        (.version // "")
        | tostring
        | gsub("^\\s+|\\s+$"; "");
      def valid_version:
        (normalized_version | length > 0)
        and ((normalized_version | ascii_downcase) != "unknown")
        and ((normalized_version | ascii_downcase) != "null")
        and ((normalized_version | ascii_downcase) != "none")
        and (normalized_version != "(none)");
      [
        .artifacts[]
        | select(.name == $pkg and valid_version)
        | normalized_version
      ] as $exact
      | if ($exact | length) > 0 then
          $exact[0]
        else
          ([
            .artifacts[]
            | select((.name | startswith($pkg + "-") or startswith($pkg + ":")) and valid_version)
            | normalized_version
          ][0] // empty)
        end
    ' "$sbom_file"
}

show_nearby_packages() {
    local main_pkg="$1"
    local nearby

    nearby=$(jq -r --arg pkg "${main_pkg}" '.artifacts[].name | select(type == "string" and contains($pkg))' "$sbom_file" | head -n5)
    if [[ -n "$nearby" ]]; then
        print_colored "$COLOR_YELLOW" "Packages containing '${main_pkg}' seen in SBOM:"
        print_colored "$COLOR_YELLOW" "$nearby"
    fi
}

extract_image_date() {
    local image_date

    if [[ "$debug_mode" == true ]]; then
        print_colored "$COLOR_CYAN" "$ jq -r '.source.metadata.config' ${sbom_file} | base64 -d | jq -r '.history[0].created'"
    fi

    image_date=$(jq -r '.source.metadata.config // empty' "$sbom_file" | base64 -d 2>/dev/null | jq -r '.history[0].created // empty' 2>/dev/null)
    if [[ -n "$image_date" ]]; then
        printf '%s\n' "$image_date"
        return 0
    fi

    image_date=$(jq -r '.source.metadata.labels["golden.container.image.build.release"] // empty' "$sbom_file")
    if [[ -n "$image_date" ]]; then
        printf '%s\n' "${image_date} (golden image date)"
        return 0
    fi

    printf '\n'
}

print_results() {
    local main_pkg="$1"
    local version="$2"
    local image_date="$3"

    printf "\n"
    print_colored "$COLOR_MAGENTA" "IMAGE: $image_url"
    print_colored "$COLOR_MAGENTA" "Image date: $image_date"
    print_colored "$COLOR_MAGENTA" "Main Package: $main_pkg"
    print_colored "$COLOR_MAGENTA" "Version: $version"
    printf "\n"
}

main() {
    local syft_source
    local main_pkg
    local version
    local image_date

    parse_args "$@"
    require_tools
    setup_temp_files

    syft_source="$(determine_syft_source)"
    generate_sbom "$syft_source"

    main_pkg="$(extract_main_package)"
    if [[ -z "$main_pkg" ]]; then
        print_colored "$COLOR_RED" "Error: Could not find main package label in image"
        exit 1
    fi

    version="$(extract_package_version "$main_pkg")"
    if [[ -z "$version" ]]; then
        print_colored "$COLOR_RED" "Error: Could not find version for package '$main_pkg'"
        show_nearby_packages "$main_pkg"
        exit 1
    fi

    image_date="$(extract_image_date)"
    print_results "$main_pkg" "$version" "$image_date"
}

main "$@"
