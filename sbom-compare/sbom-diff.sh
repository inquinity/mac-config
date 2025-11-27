#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.1
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/docker/sbom-compare/sbom-diff.sh

# SBOM Comparison Tool
# This tool uses syft to generate SBOMs for two Docker images and compares their manifests

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to display usage
usage() {
    echo "Usage: $0 <image1> <image2> [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -o, --output DIR    Output directory for SBOM files (default: ./sbom-output)"
    echo "  -v, --verbose       Verbose output"
    echo "  -k, --keep-files    Keep intermediate SBOM files after comparison"
    echo ""
    echo "Examples:"
    echo "  $0 ubuntu:20.04 ubuntu:22.04"
    echo "  $0 nginx:latest nginx:alpine -o /tmp/sbom-results"
    echo ""
}

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Function to check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    if ! command -v syft &> /dev/null; then
        missing_tools+=("syft")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_colored ${COLOR_RED} "Error: Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "syft")
                    echo "  syft: https://github.com/anchore/syft#installation"
                    echo "    brew install syft"
                    echo "    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
                    ;;
                "jq")
                    echo "  jq: https://stedolan.github.io/jq/download/"
                    echo "    brew install jq"
                    echo "    apt-get install jq"
                    ;;
            esac
        done
        exit 1
    fi
}

# Function to generate SBOM for an image
generate_sbom() {
    local image=$1
    local output_file=$2
    local verbose=${3:-false}
    
    printf "${COLOR_BLUE}Generating SBOM for ${image}...${COLOR_RESET}\n"
    
    if [ "$verbose" = true ]; then
        syft "${image}" -o github-json > "${output_file}"
    else
        syft "${image}" -o github-json > "${output_file}" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        printf "${COLOR_GREEN}✓ SBOM generated successfully: ${output_file}${COLOR_RESET}\n"
    else
        printf "${COLOR_RED}✗ Failed to generate SBOM for ${image}${COLOR_RESET}\n"
        exit 1
    fi
}

# Function to extract and sort manifest packages
extract_manifest_packages() {
    local sbom_file=$1
    local output_file=$2
    
    # Extract all package URLs from the manifests section and sort them
    jq -r '.manifests | to_entries[] | .value.resolved | keys[]' "${sbom_file}" | sort > "${output_file}"
}

# Function to compare manifests
compare_manifests() {
    local image1=$1
    local image2=$2
    local sbom1=$3
    local sbom2=$4
    local output_dir=$5
    
    local packages1="${output_dir}/packages1.tmp"
    local packages2="${output_dir}/packages2.tmp"
    
    printf "${COLOR_BLUE}Extracting manifest packages...${COLOR_RESET}\n"
    
    extract_manifest_packages "${sbom1}" "${packages1}"
    extract_manifest_packages "${sbom2}" "${packages2}"
    
    local count1=$(wc -l < "${packages1}")
    local count2=$(wc -l < "${packages2}")
    
    printf "${COLOR_YELLOW}=== SBOM Comparison Results ===${COLOR_RESET}\n"
    echo ""
    printf "${COLOR_BLUE}Image 1: ${image1}${COLOR_RESET}\n"
    echo "  Total packages: ${count1}"
    echo ""
    printf "${COLOR_BLUE}Image 2: ${image2}${COLOR_RESET}\n"
    echo "  Total packages: ${count2}"
    echo ""
    
    # Find packages only in image1
    local only_in_1="${output_dir}/only_in_image1.txt"
    comm -23 "${packages1}" "${packages2}" > "${only_in_1}"
    local only_1_count=$(wc -l < "${only_in_1}")
    
    # Find packages only in image2
    local only_in_2="${output_dir}/only_in_image2.txt"
    comm -13 "${packages1}" "${packages2}" > "${only_in_2}"
    local only_2_count=$(wc -l < "${only_in_2}")
    
    # Find common packages
    local common="${output_dir}/common_packages.txt"
    comm -12 "${packages1}" "${packages2}" > "${common}"
    local common_count=$(wc -l < "${common}")
    
    printf "${COLOR_GREEN}Common packages: ${common_count}${COLOR_RESET}\n"
    printf "${COLOR_YELLOW}Packages only in ${image1}: ${only_1_count}${COLOR_RESET}\n"
    printf "${COLOR_YELLOW}Packages only in ${image2}: ${only_2_count}${COLOR_RESET}\n"
    echo ""
    
    # Display differences
    if [ ${only_1_count} -gt 0 ]; then
        printf "${COLOR_YELLOW}Packages only in ${image1}:${COLOR_RESET}\n"
        while IFS= read -r package; do
            echo "  - ${package}"
        done < "${only_in_1}"
        echo ""
    fi
    
    if [ ${only_2_count} -gt 0 ]; then
        printf "${COLOR_YELLOW}Packages only in ${image2}:${COLOR_RESET}\n"
        while IFS= read -r package; do
            echo "  + ${package}"
        done < "${only_in_2}"
        echo ""
    fi
    
    # Save detailed comparison results
    local comparison_file="${output_dir}/comparison_results.txt"
    {
        echo "SBOM Comparison Results"
        echo "======================"
        echo ""
        echo "Image 1: ${image1}"
        echo "Total packages: ${count1}"
        echo ""
        echo "Image 2: ${image2}"
        echo "Total packages: ${count2}"
        echo ""
        echo "Common packages: ${common_count}"
        echo "Packages only in image1: ${only_1_count}"
        echo "Packages only in image2: ${only_2_count}"
        echo ""
        echo "=== Packages only in ${image1} ==="
        cat "${only_in_1}"
        echo ""
        echo "=== Packages only in ${image2} ==="
        cat "${only_in_2}"
        echo ""
        echo "=== Common packages ==="
        cat "${common}"
    } > "${comparison_file}"
    
    printf "${COLOR_GREEN}Detailed comparison saved to: ${comparison_file}${COLOR_RESET}\n"
    
    # Clean up temporary files
    rm -f "${packages1}" "${packages2}" "${only_in_1}" "${only_in_2}" "${common}"
}

# Function to sanitize image name for filename
sanitize_image_name() {
    local image=$1
    echo "${image}" | sed 's|[/:@]|-|g'
}

# Main function
main() {
    local image1=""
    local image2=""
    local output_dir="./sbom-output"
    local verbose=false
    local keep_files=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -k|--keep-files)
                keep_files=true
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [ -z "$image1" ]; then
                    image1=$1
                elif [ -z "$image2" ]; then
                    image2=$1
                else
                    echo "Too many arguments"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [ -z "$image1" ] || [ -z "$image2" ]; then
        echo "Error: Please provide two Docker images to compare"
        usage
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Create output directory
    mkdir -p "${output_dir}"
    
    # Generate sanitized filenames
    local image1_safe=$(sanitize_image_name "${image1}")
    local image2_safe=$(sanitize_image_name "${image2}")
    
    local sbom1="${output_dir}/${image1_safe}_sbom.json"
    local sbom2="${output_dir}/${image2_safe}_sbom.json"
    
    # Generate SBOMs
    generate_sbom "${image1}" "${sbom1}" "${verbose}"
    generate_sbom "${image2}" "${sbom2}" "${verbose}"
    
    # Compare manifests
    compare_manifests "${image1}" "${image2}" "${sbom1}" "${sbom2}" "${output_dir}"
    
    # Clean up SBOM files if not keeping them
    if [ "$keep_files" = false ]; then
        rm -f "${sbom1}" "${sbom2}"
        printf "${COLOR_BLUE}Cleaned up intermediate SBOM files${COLOR_RESET}\n"
    else
        printf "${COLOR_BLUE}SBOM files preserved:${COLOR_RESET}\n"
        echo "  ${sbom1}"
        echo "  ${sbom2}"
    fi
    
    printf "${COLOR_GREEN}Comparison completed successfully!${COLOR_RESET}\n"
}

# Run main function with all arguments
main "$@"
