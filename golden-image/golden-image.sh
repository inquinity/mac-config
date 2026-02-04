#!/usr/bin/env bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 2.0.0

# Requirements:
# * Docker Desktop with containerd enabled (for multi-arch local image storage)
# * Docker buildx plugin
# * crane (https://github.com/google/go-containerregistry/tree/main/cmd/crane)
# * Access to centraluhg.jfrog.io

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Configuration
JFROG_REGISTRY="centraluhg.jfrog.io"
VENDOR_PATH="glb-docker-chainguard-optum-rem/optum.com"
GOLDEN_BASE_IMAGE="${JFROG_REGISTRY}/glb-docker-uhg-loc/uhg-goldenimages/chainguard-base:latest"
PLATFORMS="linux/amd64,linux/arm64"

# Script variables
SCRIPT_NAME="$(basename "$0")"
DEBUG="false"
DRY_RUN="false"
BUILDER_NAME="${USER:-unknown}"
BUILD_DATE="$(date +%Y.%m.%d)"
BUILD_TIMESTAMP="$(date -Iseconds)"

# =============================================================================
# Usage Functions
# =============================================================================

usage_main() {
    printf 'Usage: %s <command> [arguments] [options]\n' "$SCRIPT_NAME"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Golden container image management for local development."
    printf '\n'
    print_colored "$COLOR_YELLOW" "Commands:"
    print_colored "$COLOR_CYAN" "  export    Export a vendor image as multi-architecture OCI tar"
    print_colored "$COLOR_CYAN" "  build     Build a golden image from a source (registry or tar)"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Run '%s <command> --help' for more information on a command.\n" "$SCRIPT_NAME"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Global Options:"
    print_colored "$COLOR_YELLOW" "  --debug            Show debugging information"
    print_colored "$COLOR_YELLOW" "  --help, -h         Show this help message"
}

usage_export() {
    printf 'Usage: %s export <image> [options]\n' "$SCRIPT_NAME"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Export a vendor image as a multi-architecture OCI tar file."
    print_colored "$COLOR_YELLOW" "The tar file contains both linux/amd64 and linux/arm64 variants."
    printf '\n'
    print_colored "$COLOR_YELLOW" "Arguments:"
    print_colored "$COLOR_YELLOW" "  <image>         One of the following:"
    print_colored "$COLOR_YELLOW" "                  - Short name: node:24 (uses JFrog on-corp registry)"
    print_colored "$COLOR_YELLOW" "                  - Full URL:   cgr.dev/optum.com/node:24 (direct pull)"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Options:"
    print_colored "$COLOR_YELLOW" "  --output, -o <file>  Output tar file path (default: <image>-<tag>.tar)"
    print_colored "$COLOR_YELLOW" "  --debug              Show debugging information"
    print_colored "$COLOR_YELLOW" "  --dry-run, -n        Show actions without performing them"
    print_colored "$COLOR_YELLOW" "  --help, -h           Show this help message"
    printf '\n'
    print_colored "$COLOR_BRIGHTYELLOW" "Examples:"
    print_colored "$COLOR_YELLOW" "  On-Network/VPN - uses JFrog mirror:"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME export node:24"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME export python:3.12 --output python312.tar"
    printf '\n'
    print_colored "$COLOR_YELLOW" "  Off-Network - uses Chainguard directly:"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME export cgr.dev/optum.com/node:24"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME export cgr.dev/optum.com/jdk:21 -o jdk21.tar"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Notes:"
    print_colored "$COLOR_YELLOW" "  - Requires 'crane' CLI tool (brew install crane)"
    print_colored "$COLOR_YELLOW" "  - For kafka, the source is automatically mapped to kafka-iamguarded"
    print_colored "$COLOR_YELLOW" "  - The output tar is in OCI format with multi-arch manifest"
    print_colored "$COLOR_YELLOW" "  - Use the tar file with 'build' command on any machine"
}

usage_build() {
    printf 'Usage: %s build <source> <output:tag> [options]\n' "$SCRIPT_NAME"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Build a golden container image locally with certificates and labels."
    printf '\n'
    print_colored "$COLOR_YELLOW" "Arguments:"
    print_colored "$COLOR_YELLOW" "  <source>        One of the following:"
    print_colored "$COLOR_YELLOW" "                  - Short name:   node:24 (uses JFrog on-corp registry)"
    print_colored "$COLOR_YELLOW" "                  - Full URL:     cgr.dev/optum.com/node:24 (direct pull)"
    print_colored "$COLOR_YELLOW" "                  - Tar file:     ./node-24.tar (from export command)"
    print_colored "$COLOR_YELLOW" "  <output:tag>    Output image tag (e.g., node:24-latest)"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Options:"
    print_colored "$COLOR_YELLOW" "  --builder <name>   Builder identifier for OCI label (default: \$USER)"
    print_colored "$COLOR_YELLOW" "                     Sets org.opencontainers.image.authors"
    print_colored "$COLOR_YELLOW" "  --debug            Show debugging information"
    print_colored "$COLOR_YELLOW" "  --dry-run, -n      Show actions without performing them"
    print_colored "$COLOR_YELLOW" "  --help, -h         Show this help message"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Examples:"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME build node:24 node:24-latest"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME build node:24 node:24-latest --builder you@optum.com"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME build cgr.dev/optum.com/node:24 node:24-latest"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME build ./node-24.tar node:24-latest"
    printf '\n'
    print_colored "$COLOR_BRIGHTYELLOW" "Source Types:"
    print_colored "$COLOR_YELLOW" "  On-Corp Network (VPN/Office):"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME build node:24 node:24-latest"
    print_colored "$COLOR_YELLOW" "    Uses: centraluhg.jfrog.io/glb-docker-chainguard-optum-rem/optum.com/"
    printf '\n'
    print_colored "$COLOR_YELLOW" "  Off-Corp Network (Home/Travel):"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME build cgr.dev/optum.com/node:24 node:24-latest"
    print_colored "$COLOR_YELLOW" "    Uses: Chainguard registry directly (requires auth)"
    printf '\n'
    print_colored "$COLOR_YELLOW" "  From Tar (Offline/Air-gapped):"
    print_colored "$COLOR_CYAN" "    $SCRIPT_NAME build ./node-24.tar node:24-latest"
    print_colored "$COLOR_YELLOW" "    Uses: Previously exported OCI tar file"
    printf '\n'
    print_colored "$COLOR_BRIGHTYELLOW" "Offline Workflow:"
    print_colored "$COLOR_YELLOW" "  1. On off-corp machine: Export image to tar"
    print_colored "$COLOR_CYAN" "       $SCRIPT_NAME export cgr.dev/optum.com/node:24 -o node-24.tar"
    print_colored "$COLOR_YELLOW" "  2. Transfer tar to on-corp machine"
    print_colored "$COLOR_YELLOW" "  3. Build golden image from tar"
    print_colored "$COLOR_CYAN" "       $SCRIPT_NAME build ./node-24.tar node:24-latest"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Notes:"
    print_colored "$COLOR_YELLOW" "  - Builds multi-architecture images (amd64 + arm64) stored locally"
    print_colored "$COLOR_YELLOW" "  - Requires Docker Desktop with containerd enabled"
    print_colored "$COLOR_YELLOW" "  - Certificates and APK repos are copied from golden chainguard-base"
    print_colored "$COLOR_YELLOW" "  - For JDK/JRE images, Java keystore certs are also copied"
    print_colored "$COLOR_YELLOW" "  - For kafka, the source is automatically mapped to kafka-iamguarded"
}

# =============================================================================
# Utility Functions
# =============================================================================

debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        print_colored "$COLOR_MAGENTA" "[DEBUG] $1"
    fi
}

error_exit() {
    print_colored "$COLOR_RED" "ERROR: $1" >&2
    exit "${2:-1}"
}

# Handle special image mappings (e.g., kafka -> kafka-iamguarded)
get_vendor_image_name() {
    local image_name=$1
    case "$image_name" in
        kafka)
            echo "kafka-iamguarded"
            ;;
        *)
            echo "$image_name"
            ;;
    esac
}

# Determine if this is a JDK/JRE image (needs Java keystore handling)
is_java_image() {
    local image_name=$1
    case "$image_name" in
        jdk|jre)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Parse image:tag into components
parse_image_tag() {
    local input=$1
    local image_name=""
    local image_tag=""
    
    if [[ "$input" == *:* ]]; then
        image_name=$(echo "$input" | cut -d: -f1)
        image_tag=$(echo "$input" | cut -d: -f2)
    else
        image_name="$input"
        image_tag="latest"
    fi
    
    echo "$image_name|$image_tag"
}

# Check for required tools
check_tool() {
    local tool=$1
    local install_hint=$2
    if ! command -v "$tool" &>/dev/null; then
        error_exit "'$tool' is required but not installed. $install_hint"
    fi
}

# Detect if source is a full registry URL (contains / before the :)
# Examples:
#   node:24                          -> false (short name)
#   cgr.dev/optum.com/node:24        -> true (full URL)
#   centraluhg.jfrog.io/.../node:24  -> true (full URL)
is_full_registry_url() {
    local source=$1
    # If it contains a / before any :, it's a full URL
    local before_colon="${source%%:*}"
    [[ "$before_colon" == */* ]]
}

# Extract image name from a full URL or short name
# cgr.dev/optum.com/node:24 -> node
# node:24 -> node
extract_image_name_from_source() {
    local source=$1
    local name_with_tag=""
    
    if is_full_registry_url "$source"; then
        # Get the last path component (e.g., node:24 from cgr.dev/optum.com/node:24)
        name_with_tag="${source##*/}"
    else
        name_with_tag="$source"
    fi
    
    # Remove the tag
    echo "${name_with_tag%%:*}"
}

# =============================================================================
# Export Command
# =============================================================================

cmd_export() {
    local image_spec=""
    local output_file=""
    local positional_args=()
    
    # Parse export-specific arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --dry-run|-n)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                usage_export
                exit 0
                ;;
            -*)
                error_exit "Unknown option: $1" 2
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [[ ${#positional_args[@]} -lt 1 ]]; then
        print_colored "$COLOR_RED" "ERROR: Missing required argument: <image:tag>"
        printf '\n'
        usage_export
        exit 2
    fi
    
    image_spec="${positional_args[0]}"
    
    # Check for crane
    check_tool "crane" "Install with: brew install crane"
    
    # Determine if this is a full URL or short name
    local full_image=""
    local image_name=""
    local image_tag=""
    
    if is_full_registry_url "$image_spec"; then
        # Full URL provided (e.g., cgr.dev/optum.com/node:24)
        full_image="$image_spec"
        image_name=$(extract_image_name_from_source "$image_spec")
        # Extract tag from the full URL
        if [[ "$image_spec" == *:* ]]; then
            image_tag="${image_spec##*:}"
        else
            image_tag="latest"
        fi
        debug_log "Using full URL directly: $full_image"
    else
        # Short name (e.g., node:24) - use JFrog on-corp registry
        local parsed
        parsed=$(parse_image_tag "$image_spec")
        image_name="${parsed%%|*}"
        image_tag="${parsed##*|}"
        
        # Apply image name mappings (e.g., kafka -> kafka-iamguarded)
        local vendor_image_name
        vendor_image_name=$(get_vendor_image_name "$image_name")
        
        full_image="${JFROG_REGISTRY}/${VENDOR_PATH}/${vendor_image_name}:${image_tag}"
        debug_log "Using JFrog on-corp registry: $full_image"
    fi
    
    # Determine output file
    if [[ -z "$output_file" ]]; then
        output_file="${image_name}-${image_tag}.tar"
    fi
    
    debug_log "Image spec: $image_spec"
    debug_log "Image name: $image_name"
    debug_log "Image tag: $image_tag"
    debug_log "Full image path: $full_image"
    debug_log "Output file: $output_file"
    
    print_colored "$COLOR_BRIGHTYELLOW" "Exporting multi-arch image: $full_image"
    print_colored "$COLOR_YELLOW" "Platforms: $PLATFORMS"
    print_colored "$COLOR_YELLOW" "Output: $output_file"
    printf '\n'
    
    # Create temp directory for OCI layout
    EXPORT_TEMP_DIR=$(mktemp -d)
    local oci_dir="${EXPORT_TEMP_DIR}/oci"
    
    cleanup_export() {
        debug_log "Cleaning up temporary directory: $EXPORT_TEMP_DIR"
        rm -rf "$EXPORT_TEMP_DIR"
    }
    trap cleanup_export EXIT
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: crane pull --format=oci --platform=all $full_image $oci_dir"
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: tar -cf $output_file -C $oci_dir ."
    else
        # Pull as OCI layout (preserves multi-arch)
        print_colored "$COLOR_BRIGHTYELLOW" "Pulling image with crane..."
        crane pull --format=oci --platform=all "$full_image" "$oci_dir" || \
            error_exit "Failed to pull image: $full_image"
        
        # Create tar archive
        print_colored "$COLOR_BRIGHTYELLOW" "Creating tar archive..."
        tar -cf "$output_file" -C "$oci_dir" . || \
            error_exit "Failed to create tar archive"
    fi
    
    printf '\n'
    print_colored "$COLOR_GREEN" "============================================"
    print_colored "$COLOR_GREEN" "Successfully exported multi-arch image!"
    print_colored "$COLOR_GREEN" "============================================"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Source:    $full_image"
    print_colored "$COLOR_YELLOW" "Output:    $output_file"
    print_colored "$COLOR_YELLOW" "Platforms: $PLATFORMS"
    
    if [[ "$DRY_RUN" != "true" && -f "$output_file" ]]; then
        local file_size
        file_size=$(ls -lh "$output_file" | awk '{print $5}')
        print_colored "$COLOR_YELLOW" "Size:      $file_size"
    fi
    
    printf '\n'
    print_colored "$COLOR_GREEN" "To build a golden image from this tar:"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME build $output_file ${image_name}:${image_tag}-latest"
}

# =============================================================================
# Build Command
# =============================================================================

cmd_build() {
    local source=""
    local output_tag=""
    local positional_args=()
    
    # Parse build-specific arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --builder)
                BUILDER_NAME="$2"
                shift 2
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --dry-run|-n)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                usage_build
                exit 0
                ;;
            -*)
                error_exit "Unknown option: $1" 2
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [[ ${#positional_args[@]} -lt 2 ]]; then
        print_colored "$COLOR_RED" "ERROR: Missing required arguments: <source> <output:tag>"
        printf '\n'
        usage_build
        exit 2
    fi
    
    source="${positional_args[0]}"
    output_tag="${positional_args[1]}"
    
    debug_log "Source: $source"
    debug_log "Output tag: $output_tag"
    debug_log "Builder: $BUILDER_NAME"
    debug_log "Build date: $BUILD_DATE"
    
    # Check for buildx
    if ! docker buildx version &>/dev/null; then
        error_exit "docker buildx is required for multi-architecture builds. Please install Docker Desktop or the buildx plugin."
    fi
    
    # Detect input mode (tar file vs registry)
    local input_mode="registry"
    local source_image=""
    local image_name=""
    local vendor_tag=""
    
    if [[ "$source" == *.tar ]]; then
        input_mode="tar"
        if [[ ! -f "$source" ]]; then
            error_exit "Tar file not found: $source"
        fi
        
        # For tar files, extract image name from output tag
        local parsed
        parsed=$(parse_image_tag "$output_tag")
        image_name="${parsed%%|*}"
        vendor_tag="tar-import"
        
        # The source image will be loaded into a temporary tag
        source_image="golden-build-temp:$$"
        
    elif is_full_registry_url "$source"; then
        # Full URL provided (e.g., cgr.dev/optum.com/node:24)
        source_image="$source"
        image_name=$(extract_image_name_from_source "$source")
        # Extract tag from the full URL
        if [[ "$source" == *:* ]]; then
            vendor_tag="${source##*:}"
        else
            vendor_tag="latest"
        fi
        debug_log "Using full URL directly: $source_image"
        
    else
        # Short name (e.g., node:24) - use JFrog on-corp registry
        local parsed
        parsed=$(parse_image_tag "$source")
        image_name="${parsed%%|*}"
        vendor_tag="${parsed##*|}"
        
        # Apply image name mappings and build full path
        local vendor_image_name
        vendor_image_name=$(get_vendor_image_name "$image_name")
        source_image="${JFROG_REGISTRY}/${VENDOR_PATH}/${vendor_image_name}:${vendor_tag}"
        debug_log "Using JFrog on-corp registry: $source_image"
    fi
    
    local build_tag
    build_tag=$(echo "$output_tag" | cut -d: -f2)
    
    debug_log "Input mode: $input_mode"
    debug_log "Image name: $image_name"
    debug_log "Vendor tag: $vendor_tag"
    debug_log "Build tag: $build_tag"
    debug_log "Source image: $source_image"
    
    # Create temporary directory for Dockerfile
    BUILD_TEMP_DIR=$(mktemp -d)
    local dockerfile="${BUILD_TEMP_DIR}/Dockerfile"
    
    cleanup_build() {
        debug_log "Cleaning up temporary directory: $BUILD_TEMP_DIR"
        rm -rf "$BUILD_TEMP_DIR"
        # Clean up temp image if we created one
        if [[ "${BUILD_INPUT_MODE:-}" == "tar" && "$DRY_RUN" != "true" ]]; then
            docker rmi "${BUILD_SOURCE_IMAGE:-}" &>/dev/null || true
        fi
    }
    trap cleanup_build EXIT
    
    # Store for cleanup function
    BUILD_INPUT_MODE="$input_mode"
    BUILD_SOURCE_IMAGE="$source_image"
    
    # Handle tar file: load into buildx
    if [[ "$input_mode" == "tar" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "Loading OCI tar into Docker..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_colored "$COLOR_CYAN" "[DRY-RUN] Would load tar file: $source"
        else
            # Extract tar and import as OCI
            local oci_extract_dir="${BUILD_TEMP_DIR}/oci"
            mkdir -p "$oci_extract_dir"
            tar -xf "$source" -C "$oci_extract_dir" || error_exit "Failed to extract tar file"
            
            # Use crane to push to local daemon
            check_tool "crane" "Install with: brew install crane"
            crane push "$oci_extract_dir" "$source_image" || error_exit "Failed to load image from tar"
            
            print_colored "$COLOR_GREEN" "Loaded image as: $source_image"
        fi
    fi
    
    print_colored "$COLOR_BRIGHTYELLOW" "Generating Dockerfile..."
    
    # Generate Dockerfile based on image type
    if is_java_image "$image_name"; then
        debug_log "Using Java-specific Dockerfile (includes keystore)"
        
        cat > "$dockerfile" <<EOF
# Golden Container Image - Local Build
# Generated: ${BUILD_TIMESTAMP}
# Builder: ${BUILDER_NAME}

# Stage 1: Get certificates and APK repositories from production golden base
FROM ${GOLDEN_BASE_IMAGE} AS certs

# Stage 2: Get Java keystore from golden JDK dev image
FROM ${JFROG_REGISTRY}/glb-docker-uhg-loc/uhg-goldenimages/${image_name}:latest-dev AS java-certs

# Stage 3: Build final image
FROM ${source_image}

# Copy certificates bundle from golden base
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy APK repositories from golden base
COPY --from=certs /etc/apk/repositories /etc/apk/repositories

# Copy Java keystore from golden JDK
COPY --from=java-certs /etc/ssl/certs/java/cacerts /etc/ssl/certs/java/cacerts

# Standard golden image labels
LABEL golden.container.image.type=${image_name}
LABEL golden.container.image.build.tag=${build_tag}
LABEL golden.container.image.vendor.tag=${vendor_tag}
LABEL golden.container.image.build.release=${BUILD_DATE}

# OCI standard labels
LABEL org.opencontainers.image.authors=${BUILDER_NAME}
LABEL org.opencontainers.image.created=${BUILD_TIMESTAMP}
EOF
    else
        debug_log "Using standard Dockerfile"
        
        cat > "$dockerfile" <<EOF
# Golden Container Image - Local Build
# Generated: ${BUILD_TIMESTAMP}
# Builder: ${BUILDER_NAME}

# Stage 1: Get certificates and APK repositories from production golden base
FROM ${GOLDEN_BASE_IMAGE} AS certs

# Stage 2: Build final image
FROM ${source_image}

# Copy certificates bundle from golden base
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy APK repositories from golden base
COPY --from=certs /etc/apk/repositories /etc/apk/repositories

# Standard golden image labels
LABEL golden.container.image.type=${image_name}
LABEL golden.container.image.build.tag=${build_tag}
LABEL golden.container.image.vendor.tag=${vendor_tag}
LABEL golden.container.image.build.release=${BUILD_DATE}

# OCI standard labels
LABEL org.opencontainers.image.authors=${BUILDER_NAME}
LABEL org.opencontainers.image.created=${BUILD_TIMESTAMP}
EOF
    fi
    
    if [[ "$DEBUG" == "true" ]]; then
        print_colored "$COLOR_MAGENTA" "--- Generated Dockerfile ---"
        cat "$dockerfile"
        print_colored "$COLOR_MAGENTA" "--- End Dockerfile ---"
    fi
    
    # Pull required base images
    print_colored "$COLOR_BRIGHTYELLOW" "Pulling golden chainguard-base for certificates..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker pull $GOLDEN_BASE_IMAGE"
    else
        docker pull "$GOLDEN_BASE_IMAGE" || error_exit "Failed to pull golden base image"
    fi
    
    if [[ "$input_mode" == "registry" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "Pulling vendor image: $source_image"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker pull $source_image"
        else
            docker pull "$source_image" || error_exit "Failed to pull vendor image: $source_image"
        fi
    fi
    
    if is_java_image "$image_name"; then
        local java_certs_image="${JFROG_REGISTRY}/glb-docker-uhg-loc/uhg-goldenimages/${image_name}:latest-dev"
        print_colored "$COLOR_BRIGHTYELLOW" "Pulling Java certs image: $java_certs_image"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker pull $java_certs_image"
        else
            docker pull "$java_certs_image" || error_exit "Failed to pull Java certs image"
        fi
    fi
    
    # Build the image using buildx with containerd store
    print_colored "$COLOR_BRIGHTYELLOW" "Building golden image: $output_tag"
    print_colored "$COLOR_YELLOW" "Platforms: $PLATFORMS"
    printf '\n'
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker buildx build --platform $PLATFORMS --tag $output_tag --output type=image,store=true --file $dockerfile $BUILD_TEMP_DIR"
    else
        docker buildx build \
            --platform "$PLATFORMS" \
            --tag "$output_tag" \
            --output type=image,store=true \
            --file "$dockerfile" \
            "$BUILD_TEMP_DIR" || error_exit "Docker buildx build failed"
    fi
    
    # Success output
    printf '\n'
    print_colored "$COLOR_GREEN" "============================================"
    print_colored "$COLOR_GREEN" "Successfully built golden image!"
    print_colored "$COLOR_GREEN" "============================================"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Image:        $output_tag"
    print_colored "$COLOR_YELLOW" "Source:       $source_image"
    print_colored "$COLOR_YELLOW" "Platforms:    $PLATFORMS"
    print_colored "$COLOR_YELLOW" "Builder:      $BUILDER_NAME"
    print_colored "$COLOR_YELLOW" "Build Date:   $BUILD_DATE"
    printf '\n'
    
    if [[ "$DRY_RUN" != "true" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "Verifying labels..."
        docker inspect "$output_tag" --format '{{json .Config.Labels}}' 2>/dev/null | python3 -m json.tool 2>/dev/null || \
            docker inspect "$output_tag" --format '{{json .Config.Labels}}' 2>/dev/null || \
            print_colored "$COLOR_YELLOW" "(Labels inspection requires single-arch image reference)"
        
        printf '\n'
        print_colored "$COLOR_GREEN" "To run the image (native architecture):"
        print_colored "$COLOR_CYAN" "  docker run --rm -it --user root --entrypoint sh $output_tag"
        printf '\n'
        print_colored "$COLOR_GREEN" "To run specific architecture:"
        print_colored "$COLOR_CYAN" "  docker run --rm --platform linux/amd64 -it --user root --entrypoint sh $output_tag"
        print_colored "$COLOR_CYAN" "  docker run --rm --platform linux/arm64 -it --user root --entrypoint sh $output_tag"
        printf '\n'
        print_colored "$COLOR_GREEN" "To verify certificates:"
        print_colored "$COLOR_CYAN" "  docker run --rm --user root --entrypoint sh $output_tag -c 'head -20 /etc/ssl/certs/ca-certificates.crt'"
        printf '\n'
        print_colored "$COLOR_GREEN" "To verify APK repositories:"
        print_colored "$COLOR_CYAN" "  docker run --rm --user root --entrypoint sh $output_tag -c 'cat /etc/apk/repositories'"
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Handle no arguments
    if [[ $# -eq 0 ]]; then
        usage_main
        exit 0
    fi
    
    # Extract command
    local command="$1"
    shift
    
    case "$command" in
        export)
            cmd_export "$@"
            ;;
        build)
            cmd_build "$@"
            ;;
        --help|-h)
            usage_main
            exit 0
            ;;
        --debug)
            DEBUG="true"
            if [[ $# -gt 0 ]]; then
                main "$@"
            else
                usage_main
                exit 0
            fi
            ;;
        *)
            print_colored "$COLOR_RED" "ERROR: Unknown command: $command"
            printf '\n'
            usage_main
            exit 2
            ;;
    esac
}

main "$@"
