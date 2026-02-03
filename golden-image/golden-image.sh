#!/usr/bin/env bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.1.0

# Requirements:
# * Docker Desktop (includes buildx) or docker cli with buildx plugin
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

# Script variables
SCRIPT_NAME="$(basename "$0")"
DEBUG="false"
DRY_RUN="false"
BUILDER_NAME="${USER:-unknown}"
BUILD_DATE="$(date +%Y.%m.%d)"
BUILD_TIMESTAMP="$(date -Iseconds)"
PLATFORM="linux/amd64,linux/arm64"  # Default: build for both architectures

usage() {
    printf 'Usage: %s <source> <output_tag> [options]\n' "$SCRIPT_NAME"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Build a golden container image locally with certificates and labels."
    printf '\n'
    print_colored "$COLOR_YELLOW" "Arguments:"
    print_colored "$COLOR_YELLOW" "  <source>        Vendor image tag (e.g., node:24) or path to .tar file"
    print_colored "$COLOR_YELLOW" "  <output_tag>    Output image tag (e.g., node:24-latest)"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Options:"
    print_colored "$COLOR_YELLOW" "  --builder <name>   Name to use in local builder label (default: \$USER)"
    print_colored "$COLOR_YELLOW" "  --platform <arch>  Target platform(s) (default: linux/amd64,linux/arm64)"
    print_colored "$COLOR_YELLOW" "                     Use 'linux/amd64' or 'linux/arm64' for single-arch"
    print_colored "$COLOR_YELLOW" "  --debug            Show debugging information"
    print_colored "$COLOR_YELLOW" "  --dry-run, -n      Show actions without performing them"
    print_colored "$COLOR_YELLOW" "  --help, -h         Show this help message"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Examples:"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME node:24 node:24-latest                    # builds amd64 + arm64"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME node:24 node:24-latest --builder raltman2"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME node:24 node:24-latest --platform linux/amd64  # single arch only"
    print_colored "$COLOR_CYAN" "  $SCRIPT_NAME /path/to/node24.tar node:24-latest"
    printf '\n'
    print_colored "$COLOR_YELLOW" "Notes:"
    print_colored "$COLOR_YELLOW" "  - Always builds multi-architecture images (amd64 + arm64) by default"
    print_colored "$COLOR_YELLOW" "  - Certificates and APK repos are copied from the production golden chainguard-base image"
    print_colored "$COLOR_YELLOW" "  - For JDK/JRE images, Java keystore certs are also copied"
    print_colored "$COLOR_YELLOW" "  - For kafka, the source is automatically mapped to kafka-iamguarded"
}

debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        print_colored "$COLOR_MAGENTA" "[DEBUG] $1"
    fi
}

error_exit() {
    print_colored "$COLOR_RED" "ERROR: $1" >&2
    exit "${2:-1}"
}

# Parse arguments
SOURCE=""
OUTPUT_TAG=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --builder)
            BUILDER_NAME="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
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
            usage
            exit 0
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Validate positional arguments
if [[ ${#POSITIONAL_ARGS[@]} -lt 2 ]]; then
    print_colored "$COLOR_RED" "ERROR: Missing required arguments"
    printf '\n'
    usage
    exit 2
fi

SOURCE="${POSITIONAL_ARGS[0]}"
OUTPUT_TAG="${POSITIONAL_ARGS[1]}"

debug_log "Source: $SOURCE"
debug_log "Output tag: $OUTPUT_TAG"
debug_log "Builder: $BUILDER_NAME"
debug_log "Build date: $BUILD_DATE"

# Detect input mode (tar file vs registry)
INPUT_MODE="registry"
TAR_LOADED_TAG=""

if [[ "$SOURCE" == *.tar ]]; then
    INPUT_MODE="tar"
    if [[ ! -f "$SOURCE" ]]; then
        error_exit "Tar file not found: $SOURCE"
    fi
fi

debug_log "Input mode: $INPUT_MODE"

# Handle tar file loading early (we need to know the image tag before proceeding)
TAR_LOADED_TAG=""
if [[ "$INPUT_MODE" == "tar" ]]; then
    print_colored "$COLOR_BRIGHTYELLOW" "Loading image from tar file: $SOURCE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        # In dry-run, inspect the tar manifest to get the image name
        TAR_LOADED_TAG=$(tar -xOf "$SOURCE" manifest.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('RepoTags',['unknown:tar'])[0])" 2>/dev/null || echo "unknown:tar-import")
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker load -i $SOURCE"
        debug_log "Detected image from tar manifest: $TAR_LOADED_TAG"
    else
        # Load the tar and capture the loaded image name
        LOAD_OUTPUT=$(docker load -i "$SOURCE" 2>&1)
        debug_log "Docker load output: $LOAD_OUTPUT"
        
        # Extract the loaded image tag from output like "Loaded image: node:24"
        # Using sed for macOS compatibility (no grep -oP)
        TAR_LOADED_TAG=$(echo "$LOAD_OUTPUT" | sed -n 's/^Loaded image: //p' | head -1)
        
        if [[ -z "$TAR_LOADED_TAG" ]]; then
            error_exit "Failed to determine loaded image tag from tar file"
        fi
        
        print_colored "$COLOR_GREEN" "Loaded image: $TAR_LOADED_TAG"
    fi
fi

# Extract image name and vendor tag from source
extract_image_info() {
    local source=$1
    local loaded_tag=$2
    local image_name=""
    local vendor_tag=""
    
    if [[ "$INPUT_MODE" == "tar" ]]; then
        # For tar files, extract from the loaded image tag
        if [[ -n "$loaded_tag" && "$loaded_tag" == *:* ]]; then
            image_name=$(echo "$loaded_tag" | cut -d: -f1)
            vendor_tag=$(echo "$loaded_tag" | cut -d: -f2)
        else
            # Fallback: try to infer from output tag
            image_name=$(echo "$OUTPUT_TAG" | cut -d: -f1)
            vendor_tag="tar-import"
        fi
    else
        # Parse image:tag format
        if [[ "$source" == *:* ]]; then
            image_name=$(echo "$source" | cut -d: -f1)
            vendor_tag=$(echo "$source" | cut -d: -f2)
        else
            image_name="$source"
            vendor_tag="latest"
        fi
    fi
    
    echo "$image_name|$vendor_tag"
}

IMAGE_INFO=$(extract_image_info "$SOURCE" "$TAR_LOADED_TAG")
IMAGE_NAME=$(echo "$IMAGE_INFO" | cut -d'|' -f1)
VENDOR_TAG=$(echo "$IMAGE_INFO" | cut -d'|' -f2)
BUILD_TAG=$(echo "$OUTPUT_TAG" | cut -d: -f2)

debug_log "Image name: $IMAGE_NAME"
debug_log "Vendor tag: $VENDOR_TAG"
debug_log "Build tag: $BUILD_TAG"

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

VENDOR_IMAGE_NAME=$(get_vendor_image_name "$IMAGE_NAME")
debug_log "Vendor image name: $VENDOR_IMAGE_NAME"

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

# Build the source image reference
if [[ "$INPUT_MODE" == "tar" ]]; then
    # Tar was already loaded earlier, just use the loaded tag
    SOURCE_IMAGE="$TAR_LOADED_TAG"
else
    SOURCE_IMAGE="${JFROG_REGISTRY}/${VENDOR_PATH}/${VENDOR_IMAGE_NAME}:${VENDOR_TAG}"
fi

debug_log "Source image: $SOURCE_IMAGE"

# Create temporary Dockerfile
TEMP_DIR=$(mktemp -d)
DOCKERFILE="${TEMP_DIR}/Dockerfile"

cleanup() {
    debug_log "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

print_colored "$COLOR_BRIGHTYELLOW" "Generating Dockerfile..."

# Generate Dockerfile based on image type
if is_java_image "$IMAGE_NAME"; then
    debug_log "Using Java-specific Dockerfile (includes keystore)"
    
    cat > "$DOCKERFILE" <<EOF
# Golden Container Image - Local Build
# Generated: ${BUILD_TIMESTAMP}
# Builder: ${BUILDER_NAME}

# Stage 1: Get certificates and APK repositories from production golden base
FROM ${GOLDEN_BASE_IMAGE} AS certs

# Stage 2: Get Java keystore from golden JDK dev image
FROM centraluhg.jfrog.io/glb-docker-uhg-loc/uhg-goldenimages/${IMAGE_NAME}:latest-dev AS java-certs

# Stage 3: Build final image
FROM ${SOURCE_IMAGE}

# Copy certificates bundle from golden base
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy APK repositories from golden base
COPY --from=certs /etc/apk/repositories /etc/apk/repositories

# Copy Java keystore from golden JDK
COPY --from=java-certs /etc/ssl/certs/java/cacerts /etc/ssl/certs/java/cacerts

# Standard golden image labels
LABEL golden.container.image.type=${IMAGE_NAME}
LABEL golden.container.image.build.tag=${BUILD_TAG}
LABEL golden.container.image.vendor.tag=${VENDOR_TAG}
LABEL golden.container.image.build.release=${BUILD_DATE}

# Local build labels
LABEL golden.container.image.local.builder=${BUILDER_NAME}
LABEL golden.container.image.local.build.timestamp=${BUILD_TIMESTAMP}
EOF

else
    debug_log "Using standard Dockerfile"
    
    cat > "$DOCKERFILE" <<EOF
# Golden Container Image - Local Build
# Generated: ${BUILD_TIMESTAMP}
# Builder: ${BUILDER_NAME}

# Stage 1: Get certificates and APK repositories from production golden base
FROM ${GOLDEN_BASE_IMAGE} AS certs

# Stage 2: Build final image
FROM ${SOURCE_IMAGE}

# Copy certificates bundle from golden base
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy APK repositories from golden base
COPY --from=certs /etc/apk/repositories /etc/apk/repositories

# Standard golden image labels
LABEL golden.container.image.type=${IMAGE_NAME}
LABEL golden.container.image.build.tag=${BUILD_TAG}
LABEL golden.container.image.vendor.tag=${VENDOR_TAG}
LABEL golden.container.image.build.release=${BUILD_DATE}

# Local build labels
LABEL golden.container.image.local.builder=${BUILDER_NAME}
LABEL golden.container.image.local.build.timestamp=${BUILD_TIMESTAMP}
EOF

fi

if [[ "$DEBUG" == "true" ]]; then
    print_colored "$COLOR_MAGENTA" "--- Generated Dockerfile ---"
    cat "$DOCKERFILE"
    print_colored "$COLOR_MAGENTA" "--- End Dockerfile ---"
fi

# Pull required images
print_colored "$COLOR_BRIGHTYELLOW" "Pulling golden chainguard-base for certificates..."

if [[ "$DRY_RUN" == "true" ]]; then
    print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker pull $GOLDEN_BASE_IMAGE"
else
    docker pull "$GOLDEN_BASE_IMAGE" || error_exit "Failed to pull golden base image"
fi

if [[ "$INPUT_MODE" == "registry" ]]; then
    print_colored "$COLOR_BRIGHTYELLOW" "Pulling vendor image: $SOURCE_IMAGE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker pull $SOURCE_IMAGE"
    else
        docker pull "$SOURCE_IMAGE" || error_exit "Failed to pull vendor image: $SOURCE_IMAGE"
    fi
fi

if is_java_image "$IMAGE_NAME"; then
    JAVA_CERTS_IMAGE="centraluhg.jfrog.io/glb-docker-uhg-loc/uhg-goldenimages/${IMAGE_NAME}:latest-dev"
    print_colored "$COLOR_BRIGHTYELLOW" "Pulling Java certs image: $JAVA_CERTS_IMAGE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker pull $JAVA_CERTS_IMAGE"
    else
        docker pull "$JAVA_CERTS_IMAGE" || error_exit "Failed to pull Java certs image"
    fi
fi

# Build the image using buildx for multi-architecture support
print_colored "$COLOR_BRIGHTYELLOW" "Building golden image: $OUTPUT_TAG"
print_colored "$COLOR_YELLOW" "Platforms: $PLATFORM"

# Ensure buildx is available
if ! docker buildx version &>/dev/null; then
    error_exit "docker buildx is required for multi-architecture builds. Please install Docker Desktop or the buildx plugin."
fi

if [[ "$DRY_RUN" == "true" ]]; then
    print_colored "$COLOR_CYAN" "[DRY-RUN] Would run: docker buildx build --platform $PLATFORM --tag $OUTPUT_TAG --load --file $DOCKERFILE $TEMP_DIR"
else
    docker buildx build \
        --platform "$PLATFORM" \
        --tag "$OUTPUT_TAG" \
        --load \
        --file "$DOCKERFILE" \
        "$TEMP_DIR" || error_exit "Docker buildx build failed"
fi

# Success output
printf '\n'
print_colored "$COLOR_GREEN" "============================================"
print_colored "$COLOR_GREEN" "Successfully built golden image!"
print_colored "$COLOR_GREEN" "============================================"
printf '\n'
print_colored "$COLOR_YELLOW" "Image:        $OUTPUT_TAG"
print_colored "$COLOR_YELLOW" "Source:       $SOURCE_IMAGE"
print_colored "$COLOR_YELLOW" "Platform(s):  $PLATFORM"
print_colored "$COLOR_YELLOW" "Builder:      $BUILDER_NAME"
print_colored "$COLOR_YELLOW" "Build Date:   $BUILD_DATE"
printf '\n'

if [[ "$DRY_RUN" != "true" ]]; then
    print_colored "$COLOR_BRIGHTYELLOW" "Verifying labels..."
    docker inspect "$OUTPUT_TAG" --format '{{json .Config.Labels}}' | python3 -m json.tool 2>/dev/null || \
        docker inspect "$OUTPUT_TAG" --format '{{json .Config.Labels}}'
    
    printf '\n'
    print_colored "$COLOR_GREEN" "To run the image:"
    print_colored "$COLOR_CYAN" "  docker run --rm --interactive --tty --user root --entrypoint sh $OUTPUT_TAG"
    printf '\n'
    print_colored "$COLOR_GREEN" "To verify certificates:"
    print_colored "$COLOR_CYAN" "  docker run --rm --user root --entrypoint sh $OUTPUT_TAG -c 'cat /etc/ssl/certs/ca-certificates.crt | head -20'"
    printf '\n'
    print_colored "$COLOR_GREEN" "To verify APK repositories:"
    print_colored "$COLOR_CYAN" "  docker run --rm --user root --entrypoint sh $OUTPUT_TAG -c 'cat /etc/apk/repositories'"
fi
