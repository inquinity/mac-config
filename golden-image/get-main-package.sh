#!/bin/zsh
# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.1.0

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

CHAINGUARD_MAIN_PACKAGE_LABEL="dev.chainguard.package.main"

require_tool() {
    local tool_name="$1"
    local install_hint="$2"

    if ! whence -p "$tool_name" >/dev/null 2>&1; then
        print_colored "$COLOR_RED" "Error: Required tool '$tool_name' is not installed"
        if [[ -n "$install_hint" ]]; then
            print_colored "$COLOR_YELLOW" "Install hint: $install_hint"
        fi
        exit 1
    fi
}

is_useless_version() {
    local raw_version="$1"
    local trimmed_version
    local normalized_version

    trimmed_version=$(printf "%s" "$raw_version" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    normalized_version=$(printf "%s" "$trimmed_version" | tr '[:upper:]' '[:lower:]')

    case "$normalized_version" in
        ""|"unknown"|"missing"|"none"|"null"|"n/a"|"na"|"not available"|"unavailable")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Parse arguments
debug_mode=false
image_url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [OPTIONS] IMAGE_URL"
            print_colored "$COLOR_YELLOW" ""
            print_colored "$COLOR_YELLOW" "Options:"
            print_colored "$COLOR_YELLOW" "  --debug  Show CLI commands before execution"
            print_colored "$COLOR_YELLOW" ""
            print_colored "$COLOR_YELLOW" "Example:"
            print_colored "$COLOR_YELLOW" "  $(basename "$0") edgecore.optum.com/glb-docker-uhg-loc/uhg-goldenimages/external-dns:latest"
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
    print_colored "$COLOR_RED" "Error: IMAGE_URL is required"
    exit 1
fi

# Tool preflight checks
require_tool "jq" "brew install jq"
require_tool "syft" "brew install syft"

sbom_file="/tmp/sbom-$$.json"
cleanup_temp_files() {
    rm -f "$sbom_file"
}
trap cleanup_temp_files EXIT INT TERM

# Prefer local Docker image source first; fall back to registry if not local
scan_source="registry:${image_url}"
source_mode="registry"

if whence -p docker >/dev/null 2>&1 && command docker image inspect "$image_url" >/dev/null 2>&1; then
    scan_source="docker:${image_url}"
    source_mode="local"
    if [[ "$debug_mode" == true ]]; then
        print_colored "$COLOR_CYAN" "$ docker image inspect ${image_url} | jq -r --arg label \"${CHAINGUARD_MAIN_PACKAGE_LABEL}\" '.[0].Config.Labels[\$label] // empty'"
    fi
    main_pkg=$(command docker image inspect "$image_url" | jq -r --arg label "$CHAINGUARD_MAIN_PACKAGE_LABEL" '.[0].Config.Labels[$label] // empty')
else
    require_tool "crane" "brew install crane"
    if [[ "$debug_mode" == true ]]; then
        print_colored "$COLOR_CYAN" "$ crane config ${image_url} | jq -r --arg label \"${CHAINGUARD_MAIN_PACKAGE_LABEL}\" '.config.Labels[\$label] // empty'"
    fi
    main_pkg=$(crane config "$image_url" 2>/dev/null | jq -r --arg label "$CHAINGUARD_MAIN_PACKAGE_LABEL" '.config.Labels[$label] // empty')
fi

if [[ -z "$main_pkg" ]]; then
    print_colored "$COLOR_RED" "Error: Could not find main package label in image"
    exit 1
fi
print_colored "$COLOR_GREEN" "Image source mode: $source_mode"
print_colored "$COLOR_MAGENTA" "Chainguard main label: $main_pkg"

# Generate SBOM
print_colored "$COLOR_GREEN" "Generating SBOM for image: $image_url"
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ syft scan ${scan_source} -o syft-json > $sbom_file"
fi
syft scan "$scan_source" -o syft-json > "$sbom_file" 2>/dev/null
if [[ $? -ne 0 ]]; then
    print_colored "$COLOR_RED" "Error: Failed to generate SBOM for image"
    exit 1
fi

# Extract matching packages (name/version/type)
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ jq -r --arg pkg \"${main_pkg}\" '.artifacts[] | select(.name==\$pkg or (.name|startswith(\$pkg+\"-\")) or (.name|startswith(\$pkg+\":\"))) | [ .name, (.version // \"\"), (.type // \"unknown\") ] | @tsv' $sbom_file"
fi
matching_packages=$(jq -r --arg pkg "${main_pkg}" '
  .artifacts[]
  | select(.name==$pkg or (.name|startswith($pkg+"-")) or (.name|startswith($pkg+":")))
  | [ .name, (.version // ""), (.type // "unknown") ]
  | @tsv
' "$sbom_file")

if [[ -z "$matching_packages" ]]; then
    print_colored "$COLOR_RED" "Error: Could not find artifacts matching package '$main_pkg'"
    exit 1
fi

all_discovered_versions=""
valid_discovered_versions=""

while IFS=$'\t' read -r package_name package_version package_type; do
    if [[ -z "$package_name$package_type$package_version" ]]; then
        continue
    fi

    all_discovered_versions+="${package_type}"$'\t'"${package_version}"$'\n'

    if ! is_useless_version "$package_version"; then
        valid_discovered_versions+="${package_type}"$'\t'"${package_version}"$'\n'
    fi
done <<< "$matching_packages"

all_discovered_versions=$(printf "%s" "$all_discovered_versions" | awk 'NF && !seen[$0]++')
valid_discovered_versions=$(printf "%s" "$valid_discovered_versions" | awk 'NF && !seen[$0]++')

selected_versions="$valid_discovered_versions"
if [[ -z "$selected_versions" ]]; then
    selected_versions="$all_discovered_versions"
fi

if [[ -z "$selected_versions" ]]; then
    print_colored "$COLOR_RED" "Error: Could not determine package versions for '$main_pkg'"
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
while IFS=$'\t' read -r package_type package_version; do
    if [[ -z "$package_type$package_version" ]]; then
        continue
    fi
    print_colored "$COLOR_MAGENTA" "Main Package: $main_pkg"
    print_colored "$COLOR_MAGENTA" "Version: $package_version"
    print_colored "$COLOR_MAGENTA" "Type: $package_type"
done <<< "$selected_versions"

if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_YELLOW" ""
    print_colored "$COLOR_YELLOW" "All packages matching main package name:"
    while IFS=$'\t' read -r package_name package_version package_type; do
        if [[ -z "$package_name$package_type$package_version" ]]; then
            continue
        fi
        aligned_package_line=$(printf "    %-32s %-20s %s" "$package_name" "$package_version" "$package_type")
        print_colored "$COLOR_YELLOW" "$aligned_package_line"
    done <<< "$matching_packages"
fi
printf "\n"
