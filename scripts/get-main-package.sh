#!/bin/zsh
# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.1

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_RESET="\e[0m"          # Used to reset color formatting

print_colored() {
    printf "${1}${2}${COLOR_RESET}\n"
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
sbom_file="/tmp/sbom-$$.json"
trap "rm -f '$sbom_file'" EXIT

# Generate SBOM
print_colored "$COLOR_GREEN" "Generating SBOM for image: $image_url"
if [[ "$debug_mode" == true ]]; then
    print_colored "$COLOR_CYAN" "$ syft scan registry:${image_url} -o syft-json > $sbom_file"
fi
syft scan "registry:${image_url}" -o syft-json > "$sbom_file" 2>/dev/null
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
