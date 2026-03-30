# Anchore Tools

A minimal Wolfi Linux container with [Syft](https://github.com/anchore/syft) and [Grype](https://github.com/anchore/grype) pre-installed, designed for interactively scanning APK packages for vulnerabilities and software bill of materials (SBOM) data.

## Prerequisites

- Docker (or a compatible container runtime via the `docker` CLI)
- `yq` (optional — used to read the image name from `compose.yml`; falls back to `anchore-search:latest`)

## Setup

Source the shell library to make the `anchore` command available in your shell:

```sh
source ./anchore-functions.sh
```

Add this to your shell profile (e.g. `~/.zshrc`) to load it automatically:

```sh
source /path/to/anchore-tools/anchore-functions.sh
```

## Building

The image is built automatically on first use. To build manually:

```sh
docker build --tag anchore-search:latest .
```

Or force a rebuild through the shell library:

```sh
anchore --rebuild
```

## Usage

```
anchore [OPTION] [scanapk [--summary|--full] <package> [package ...]]
```

### Options

| Command | Description |
|---|---|
| `anchore` | Launch an interactive shell inside the container |
| `anchore --rebuild` | Force rebuild the image, then launch the shell |
| `anchore scanapk <pkg>` | Scan a package (summary mode) |
| `anchore scanapk --full <pkg>` | Full output with vulnerability summary |
| `anchore --help` | Show help |

### Inside the container

| Command | Description |
|---|---|
| `scanapk <pkg>` | Scan a package and its APK dependencies |
| `scanapk --help` | Show scanapk usage and output modes |
| `help` | Show quick reference |
| `help apk` | Show APK search syntax reference |
| `help scanapk` | Show scanapk usage details |

### Examples

```sh
# Scan a single package (summary mode — prints vulnerability counts + final Grype table)
anchore scanapk curl

# Scan multiple packages with full verbose output
anchore scanapk --full curl jq openssl

# Drop into an interactive shell to explore manually
anchore
```

## How `scanapk` works

`scanapk` creates a throwaway rootfs under `scanapk-<timestamp>/`, installs the requested APK packages into it, then runs Syft and Grype against that rootfs. This isolates the packages under test from the container's base system.

### Output files (inside the container, under `scanapk-<timestamp>/`)

| File | Contents |
|---|---|
| `syft-table.txt` | Human-readable Syft SBOM table |
| `grype-table.txt` | Human-readable Grype vulnerability findings |

### Output modes

| Mode | Syft output | Grype output | Summary |
|---|---|---|---|
| `--summary` (default) | Saved to file (silent) | Saved to file (silent) | Vulnerability counts + final Grype table printed |
| `--full` | Printed + saved | Printed + saved | Vulnerability counts printed |

## Image lifecycle

The `anchore` function checks the image age at startup and automatically rebuilds if it is older than 30 days, ensuring tools stay current.

## Files

| File | Description |
|---|---|
| `dockerfile` | Container image definition |
| `compose.yml` | Docker Compose file (defines image name) |
| `anchore-functions.sh` | Shell library — source this to use `anchore` and related functions |
| `apk-search.txt` | APK command reference (shown with `help apk`) |
