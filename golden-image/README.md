# Golden Image Builder

Build golden container images locally when the platform team is unavailable.

## Overview

This tool allows developers to create golden container images on their local machine for emergency situations when the platform team is unavailable (vacations, outages, etc.). Built images are **production-ready** and include all standard golden image labels.

The tool handles:

- **Multi-architecture builds** (linux/amd64 + linux/arm64)
- **Certificate injection** from production golden images
- **APK repository configuration** for internal package access
- **Java keystore handling** for JDK/JRE images
- **Builder identification** for traceability

## Requirements

- **Docker Desktop** with containerd enabled (for multi-arch local storage)
- **crane** CLI tool (`brew install crane`)
- Access to `centraluhg.jfrog.io` (on-corp) or `cgr.dev` (off-corp)

### Enabling Containerd in Docker Desktop

Containerd is required for storing multi-architecture images locally. To enable:

1. Open **Docker Desktop**
2. Go to **Settings** (gear icon)
3. Select **General**
4. Check **"Use containerd for pulling and storing images"**
5. Click **Apply & Restart**

Verify containerd is enabled:
```bash
docker info | grep -i "storage driver"
# Should show: Storage Driver: overlayfs (with containerd)
```

## Installation

```bash
# Clone the mac-config repository or copy the script
cp golden-image.sh ~/bin/
chmod +x ~/bin/golden-image.sh

# Or add to PATH
export PATH="$PATH:/path/to/golden-image"
```

## Commands

### `build` - Build a Golden Image

Build a golden container image from a vendor source.

```bash
golden-image.sh build <source> <output:tag> [options]
```

**Source types:**

| Type | Example | When to use |
|------|---------|-------------|
| Short name | `node:24` | On-corp network (VPN/Office) |
| Full URL | `cgr.dev/optum.com/node:24` | Off-corp network (Home/Travel) |
| Tar file | `./node-24.tar` | Offline/Air-gapped |

**Examples:**

```bash
# On-corp: Uses JFrog mirror
golden-image.sh build node:24 node:24-latest

# Off-corp: Uses Chainguard directly
golden-image.sh build cgr.dev/optum.com/node:24 node:24-latest

# From tar file
golden-image.sh build ./node-24.tar node:24-latest

# With builder identification
golden-image.sh build node:24 node:24-latest --builder john.doe@optum.com
```

### `export` - Export Image as Tar

Export a vendor image as a multi-architecture OCI tar file for offline use.

```bash
golden-image.sh export <image> [options]
```

**Examples:**

```bash
# On-corp: Export from JFrog
golden-image.sh export node:24

# Off-corp: Export from Chainguard
golden-image.sh export cgr.dev/optum.com/node:24

# Custom output filename
golden-image.sh export python:3.12 --output python312.tar
```

## Workflows

### Standard On-Corp Build

```bash
# Single command - pulls from JFrog and builds
golden-image.sh build node:24 node:24-latest
```

### Off-Corp Build

```bash
# Direct pull from Chainguard (requires auth)
golden-image.sh build cgr.dev/optum.com/node:24 node:24-latest
```

### Offline/Air-Gapped Workflow

When you need to transfer images between networks:

```bash
# 1. On machine with registry access: Export to tar
golden-image.sh export cgr.dev/optum.com/node:24 -o node-24.tar

# 2. Transfer node-24.tar to target machine

# 3. On target machine: Build from tar
golden-image.sh build ./node-24.tar node:24-latest
```

## Options

| Option | Description |
|--------|-------------|
| `--builder <name>` | Builder identifier for traceability (default: `$USER`) |
| `--output, -o <file>` | Output tar file path (export only) |
| `--debug` | Show detailed debugging information |
| `--dry-run, -n` | Show actions without performing them |
| `--help, -h` | Show help message |

## Image Labels

Built images include all standard golden image labels:

**Standard golden labels** (required for enterprise tooling):
- `golden.container.image.type` - Image type (e.g., node, python, jdk)
- `golden.container.image.build.tag` - Build tag
- `golden.container.image.vendor.tag` - Original vendor tag
- `golden.container.image.build.release` - Build date

**OCI standard labels**:
- `org.opencontainers.image.authors` - Who built the image (user or email)
- `org.opencontainers.image.created` - When it was built

## Special Cases

### Java Images (JDK/JRE)

Java images automatically include the Java keystore with internal certificates:

```bash
golden-image.sh build jdk:21 jdk:21-latest
```

### Kafka

The `kafka` image name automatically maps to `kafka-iamguarded`:

```bash
golden-image.sh build kafka:3.6 kafka:3.6-latest
# Actually pulls: kafka-iamguarded:3.6
```

## Verifying Built Images

```bash
# Run the image
docker run --rm -it --user root --entrypoint sh node:24-latest

# Run specific architecture
docker run --rm --platform linux/amd64 -it --user root --entrypoint sh node:24-latest

# Check certificates
docker run --rm --user root --entrypoint sh node:24-latest -c 'head -20 /etc/ssl/certs/ca-certificates.crt'

# Check APK repositories
docker run --rm --user root --entrypoint sh node:24-latest -c 'cat /etc/apk/repositories'

# Inspect labels
docker inspect node:24-latest --format '{{json .Config.Labels}}' | jq
```

## Troubleshooting

### "crane not found"

Install crane:
```bash
brew install crane
```

### "docker buildx" errors

Ensure Docker Desktop is running with containerd enabled:
1. Docker Desktop → Settings → Features in development
2. Enable "Use containerd for pulling and storing images"

### Multi-arch build fails

Verify containerd is enabled:
```bash
docker info | grep -i containerd
```

### Registry authentication

For `cgr.dev` access, ensure you're authenticated:
```bash
crane auth login cgr.dev
```

## Author

Robert Altman, OptumRx  
robert.altman@optum.com
