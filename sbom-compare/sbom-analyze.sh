#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.0.1
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/docker/sbom-compare/sbom-analyze.sh

# Advanced SBOM Analysis Tool
# This tool provides detailed analysis of package differences between two SBOM files

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

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Function to display usage
usage() {
    printf "Usage: $0 <sbom1.json> <sbom2.json> [options]\n"
    printf "\n"
    printf "Options:\n"
    printf "  -h, --help          Show this help message\n"
    printf "  -o, --output DIR    Output directory for analysis results (default: ./analysis-output)\n"
    printf "  -d, --detailed      Show detailed package information including versions\n"
    printf "  -f, --format FORMAT Output format: text, json, csv (default: text)\n"
    printf "  -t, --type TYPE     Analysis type: packages, vulnerabilities, all (default: packages)\n"
    printf "\n"
    printf "Examples:\n"
    printf "  $0 image1-sbom.json image2-sbom.json\n"
    printf "  $0 image1-sbom.json image2-sbom.json --detailed --format json\n"
    printf "\n"
}

# Function to check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_colored ${COLOR_RED} "Error: Missing required tools: ${missing_tools[*]}"
        printf "\n"
        printf "Please install jq: brew install jq\n"
        exit 1
    fi
}

# Function to extract package details from SBOM
extract_package_details() {
    local sbom_file=$1
    local output_file=$2
    
    jq -r '
        .manifests | to_entries[] | 
        .value.resolved | to_entries[] | 
        {
            package_url: .key,
            name: (.value.package_url | split("/")[-1] | split("@")[0]),
            version: (.value.package_url | split("@")[1] | split("?")[0]),
            relationship: .value.relationship,
            scope: .value.scope,
            dependencies: (.value.dependencies // [])
        }
    ' "${sbom_file}" > "${output_file}"
}

# Function to create detailed comparison report
create_detailed_report() {
    local sbom1=$1
    local sbom2=$2
    local output_dir=$3
    local format=${4:-"text"}
    
    local details1="${output_dir}/details1.json"
    local details2="${output_dir}/details2.json"
    
    print_colored ${COLOR_BLUE} "Extracting detailed package information..."
    
    extract_package_details "${sbom1}" "${details1}"
    extract_package_details "${sbom2}" "${details2}"
    
    # Create comprehensive comparison
    local comparison_script="${output_dir}/compare.jq"
    cat > "${comparison_script}" << 'EOF'
def compare_packages(packages1; packages2):
    {
        packages1_count: (packages1 | length),
        packages2_count: (packages2 | length),
        common_packages: [
            packages1[] as $p1 | 
            packages2[] as $p2 | 
            if $p1.package_url == $p2.package_url then $p1 else empty end
        ],
        only_in_1: [
            packages1[] as $p1 | 
            if ([packages2[].package_url] | contains([$p1.package_url])) then empty else $p1 end
        ],
        only_in_2: [
            packages2[] as $p2 | 
            if ([packages1[].package_url] | contains([$p2.package_url])) then empty else $p2 end
        ],
        version_differences: [
            packages1[] as $p1 | 
            packages2[] as $p2 | 
            if ($p1.name == $p2.name and $p1.version != $p2.version) then 
                {
                    package_name: $p1.name,
                    version1: $p1.version,
                    version2: $p2.version,
                    package_url1: $p1.package_url,
                    package_url2: $p2.package_url
                }
            else empty end
        ]
    };

{
    timestamp: now | strftime("%Y-%m-%d %H:%M:%S"),
    comparison: compare_packages($packages1; $packages2)
}
EOF
    
    # Run the comparison
    local detailed_results="${output_dir}/detailed_analysis.json"
    jq -n --slurpfile packages1 "${details1}" --slurpfile packages2 "${details2}" \
        -f "${comparison_script}" > "${detailed_results}"
    
    # Generate output based on format
    case $format in
        "json")
            cp "${detailed_results}" "${output_dir}/comparison_results.json"
            print_colored ${COLOR_GREEN} "Detailed JSON analysis saved to: ${output_dir}/comparison_results.json"
            ;;
        "csv")
            generate_csv_report "${detailed_results}" "${output_dir}"
            ;;
        "text"|*)
            generate_text_report "${detailed_results}" "${output_dir}"
            ;;
    esac
    
    # Clean up temporary files
    rm -f "${details1}" "${details2}" "${comparison_script}"
}

# Function to generate text report
generate_text_report() {
    local results_file=$1
    local output_dir=$2
    local report_file="${output_dir}/detailed_report.txt"
    
    {
        echo "=== DETAILED SBOM ANALYSIS REPORT ==="
        echo "Generated: $(jq -r '.timestamp' "${results_file}")"
        echo ""
        
        echo "=== SUMMARY ==="
        echo "Packages in SBOM 1: $(jq -r '.comparison.packages1_count' "${results_file}")"
        echo "Packages in SBOM 2: $(jq -r '.comparison.packages2_count' "${results_file}")"
        echo "Common packages: $(jq -r '.comparison.common_packages | length' "${results_file}")"
        echo "Packages only in SBOM 1: $(jq -r '.comparison.only_in_1 | length' "${results_file}")"
        echo "Packages only in SBOM 2: $(jq -r '.comparison.only_in_2 | length' "${results_file}")"
        echo "Version differences: $(jq -r '.comparison.version_differences | length' "${results_file}")"
        echo ""
        
        echo "=== PACKAGES ONLY IN SBOM 1 ==="
        jq -r '.comparison.only_in_1[] | "  \(.name) (\(.version)) - \(.package_url)"' "${results_file}"
        echo ""
        
        echo "=== PACKAGES ONLY IN SBOM 2 ==="
        jq -r '.comparison.only_in_2[] | "  \(.name) (\(.version)) - \(.package_url)"' "${results_file}"
        echo ""
        
        echo "=== VERSION DIFFERENCES ==="
        jq -r '.comparison.version_differences[] | "  \(.package_name): \(.version1) → \(.version2)"' "${results_file}"
        echo ""
        
        echo "=== COMMON PACKAGES ==="
        jq -r '.comparison.common_packages[] | "  \(.name) (\(.version))"' "${results_file}"
        
    } > "${report_file}"
    
    print_colored ${COLOR_GREEN} "Detailed text report saved to: ${report_file}"
}

# Function to generate CSV report
generate_csv_report() {
    local results_file=$1
    local output_dir=$2
    
    # Generate CSV for packages only in SBOM 1
    local csv1="${output_dir}/packages_only_in_sbom1.csv"
    {
        echo "Package Name,Version,Package URL,Relationship,Scope"
        jq -r '.comparison.only_in_1[] | [.name, .version, .package_url, .relationship, .scope] | @csv' "${results_file}"
    } > "${csv1}"
    
    # Generate CSV for packages only in SBOM 2
    local csv2="${output_dir}/packages_only_in_sbom2.csv"
    {
        echo "Package Name,Version,Package URL,Relationship,Scope"
        jq -r '.comparison.only_in_2[] | [.name, .version, .package_url, .relationship, .scope] | @csv' "${results_file}"
    } > "${csv2}"
    
    # Generate CSV for version differences
    local csv3="${output_dir}/version_differences.csv"
    {
        echo "Package Name,Version in SBOM1,Version in SBOM2,Package URL SBOM1,Package URL SBOM2"
        jq -r '.comparison.version_differences[] | [.package_name, .version1, .version2, .package_url1, .package_url2] | @csv' "${results_file}"
    } > "${csv3}"
    
    print_colored ${COLOR_GREEN} "CSV reports generated:"
    print_colored ${COLOR_GREEN} "  - ${csv1}"
    print_colored ${COLOR_GREEN} "  - ${csv2}"
    print_colored ${COLOR_GREEN} "  - ${csv3}"
}

# Function to display quick summary
display_quick_summary() {
    local sbom1=$1
    local sbom2=$2
    
    local count1=$(jq '.manifests | to_entries[] | .value.resolved | keys | length' "${sbom1}" | paste -sd+ - | bc)
    local count2=$(jq '.manifests | to_entries[] | .value.resolved | keys | length' "${sbom2}" | paste -sd+ - | bc)
    
    print_colored ${COLOR_CYAN} "=== QUICK SUMMARY ==="
    print_colored ${COLOR_BLUE} "SBOM 1: ${sbom1}"
    printf "  Total packages: ${count1}\n"
    print_colored ${COLOR_BLUE} "SBOM 2: ${sbom2}"
    printf "  Total packages: ${count2}\n"
    printf "\n"
}

# Main function
main() {
    local sbom1=""
    local sbom2=""
    local output_dir="./analysis-output"
    local detailed=false
    local format="text"
    local analysis_type="packages"
    
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
            -d|--detailed)
                detailed=true
                shift
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -t|--type)
                analysis_type="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [ -z "$sbom1" ]; then
                    sbom1=$1
                elif [ -z "$sbom2" ]; then
                    sbom2=$1
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
    if [ -z "$sbom1" ] || [ -z "$sbom2" ]; then
        echo "Error: Please provide two SBOM files to compare"
        usage
        exit 1
    fi
    
    # Check if files exist
    if [ ! -f "$sbom1" ]; then
        print_colored ${COLOR_RED} "Error: SBOM file not found: ${sbom1}"
        exit 1
    fi
    
    if [ ! -f "$sbom2" ]; then
        print_colored ${COLOR_RED} "Error: SBOM file not found: ${sbom2}"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Create output directory
    mkdir -p "${output_dir}"
    
    # Display quick summary
    display_quick_summary "${sbom1}" "${sbom2}"
    
    # Perform detailed analysis if requested
    if [ "$detailed" = true ]; then
        create_detailed_report "${sbom1}" "${sbom2}" "${output_dir}" "${format}"
    fi
    
    print_colored ${COLOR_GREEN} "Analysis completed successfully!"
}

# Run main function with all arguments
main "$@"
