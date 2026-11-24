#!/bin/bash
#
# install-tools.sh -- install the inquinity utilities on an Intel Mac without brew.
#
# Homebrew 7 dropped Intel support, so this reads the cask definitions from the
# inquinity/homebrew-tap repository (the source of truth for version, URL,
# SHA-256 and minimum macOS) and installs each app directly into /Applications.
#
# Tools (only these; nothing external is ever installed):
#   - yatu                           (Finder terminal button, macOS 13+)
#     or openinterminal-lite-inquinity (same job, macOS 12+) -- whichever the OS supports
#   - qltextview
#   - belvedere
#
# Written for bash 3.2 (/bin/bash on old macOS): no associative arrays, mapfile, etc.
#
# Test hooks (environment): INTEL_TOOLS_TAP_BASE, INTEL_TOOLS_MACOS_VERSION,
# INTEL_TOOLS_APP_DIR, INTEL_TOOLS_STATE_FILE, INTEL_TOOLS_ALLOW_ARM64.

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_CYAN="\e[36m"          # Informational messages
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

TAP_BASE="${INTEL_TOOLS_TAP_BASE:-https://raw.githubusercontent.com/inquinity/homebrew-tap/main/Casks}"
APP_DIR="${INTEL_TOOLS_APP_DIR:-/Applications}"
STATE_FILE="${INTEL_TOOLS_STATE_FILE:-${HOME}/.config/mac-config/intel-tools.state}"

# Expected Developer ID Team ID per cask (Altman Software Design, LLC). Empty
# means "not pinned": the app must still be validly signed and notarized, and
# its Team ID is printed.
expected_team_id() {
    case "$1" in
        yatu|openinterminal-lite-inquinity|qltextview|belvedere) printf '45GJWJVQN2' ;;
        *)         printf '' ;;
    esac
}

usage() {
    printf "${COLOR_YELLOW}Install inquinity utilities on an Intel Mac (no brew)${COLOR_RESET}\n"
    printf "Usage: %s [--dry-run|-n] [--list|-l] [--yes|-y] [--only NAME] [--help|-h]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  --dry-run, -n   Show what would be installed; download nothing\n"
    printf "  --list, -l      Show what would be installed or skipped on this Mac\n"
    printf "  --yes, -y       Do not ask for confirmation\n"
    printf "  --only NAME     Handle only one cask (yatu, openinterminal-lite-inquinity,\n"
    printf "                  qltextview, belvedere)\n"
    printf "  --help, -h      Show this help message\n"
}

DRY_RUN=0
LIST_ONLY=0
ASSUME_YES=0
ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --list|-l)    LIST_ONLY=1; shift ;;
        --yes|-y)     ASSUME_YES=1; shift ;;
        --only)
            [[ $# -ge 2 ]] || { print_colored "$COLOR_RED" "--only needs a name"; exit 1; }
            ONLY=$2; shift 2 ;;
        --help|-h)    usage; exit 0 ;;
        *)
            print_colored "$COLOR_RED" "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "$(uname)" != "Darwin" ]]; then
    print_colored "$COLOR_RED" "This script only supports macOS."
    exit 1
fi

if [[ -z "${INTEL_TOOLS_ALLOW_ARM64:-}" && "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
    print_colored "$COLOR_RED" "This is an Apple Silicon Mac; install these with brew instead."
    exit 1
fi

# --- macOS version handling ---------------------------------------------------

# Turn a version like 13.6.1 or 10.15.7 into a comparable number: 1300, 1015.
version_key() {
    local v=$1 major minor
    major=${v%%.*}
    if [[ "$major" == "10" ]]; then
        minor=${v#10.}; minor=${minor%%.*}
        printf '%d' $((1000 + minor))
    else
        printf '%d' $((major * 100))
    fi
}

# Map a cask's `depends_on macos: :name` symbol to a comparable number.
macos_symbol_key() {
    case "$1" in
        catalina) printf '1015' ;;
        big_sur)  printf '1100' ;;
        monterey) printf '1200' ;;
        ventura)  printf '1300' ;;
        sonoma)   printf '1400' ;;
        sequoia)  printf '1500' ;;
        tahoe)    printf '2600' ;;
        *)        return 1 ;;
    esac
}

OS_VERSION="${INTEL_TOOLS_MACOS_VERSION:-$(sw_vers -productVersion)}"
OS_KEY=$(version_key "$OS_VERSION")

# --- Cask parsing -------------------------------------------------------------

TMP_DIR=""
MOUNT_POINT=""
cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet -force >/dev/null 2>&1 || true
    fi
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/intel-tools.XXXXXX")

# Cask fields, set by load_cask.
C_VERSION="" C_SHA="" C_URL="" C_APP="" C_MIN_KEY="" C_MIN_NAME=""

cask_field() {  # cask_field FILE REGEX-with-one-group
    sed -n "s/^[[:space:]]*$2.*/\\1/p" "$1" | head -1
}

load_cask() {
    local name=$1 file="$TMP_DIR/$1.rb" symbol
    curl --fail --silent --show-error --location --max-time 30 \
        -o "$file" "${TAP_BASE}/${name}.rb" || return 1

    C_VERSION=$(cask_field "$file" 'version "\([^"]*\)"')
    C_SHA=$(cask_field "$file" 'sha256 "\([0-9a-f]\{64\}\)"')
    C_URL=$(cask_field "$file" 'url "\([^"]*\)"')
    C_APP=$(cask_field "$file" 'app "\([^"]*\)"')
    symbol=$(cask_field "$file" 'depends_on macos: :\([a-z_]*\)')

    [[ -n "$C_VERSION" && -n "$C_SHA" && -n "$C_URL" && -n "$C_APP" ]] || {
        print_colored "$COLOR_RED" "${name}: could not parse the cask (version/sha256/url/app)"
        return 1
    }
    C_URL=${C_URL//\#\{version\}/$C_VERSION}
    if [[ "$C_URL" == *'#{'* ]]; then
        print_colored "$COLOR_RED" "${name}: url uses an interpolation this script does not understand: $C_URL"
        return 1
    fi
    C_MIN_NAME=$symbol
    if [[ -n "$symbol" ]]; then
        C_MIN_KEY=$(macos_symbol_key "$symbol") || {
            print_colored "$COLOR_RED" "${name}: unknown macOS symbol :${symbol}"
            return 1
        }
    else
        C_MIN_KEY=0
    fi
}

cask_caveats() {  # print the caveats heredoc, if any
    sed -n '/caveats <<~EOS/,/^[[:space:]]*EOS/p' "$TMP_DIR/$1.rb" \
        | sed '1d;$d' | sed 's/^[[:space:]]*//'
}

# --- State (installed versions) ---------------------------------------------

installed_version() {
    [[ -f "$STATE_FILE" ]] || return 0
    awk -v n="$1" '$1 == n { print $2 }' "$STATE_FILE" | tail -1
}

record_version() {
    local name=$1 version=$2 tmp
    mkdir -p "$(dirname "$STATE_FILE")"
    tmp=$(mktemp "${TMP_DIR}/state.XXXXXX")
    [[ -f "$STATE_FILE" ]] && awk -v n="$name" '$1 != n' "$STATE_FILE" > "$tmp"
    printf '%s %s\n' "$name" "$version" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# --- Install steps ------------------------------------------------------------

run_cmd() {
    if [[ -w "$APP_DIR" ]]; then "$@"; else sudo "$@"; fi
}

verify_app() {  # verify_app NAME APP_PATH
    local name=$1 app=$2 exe_name exe team want spctl_out
    exe_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null) || {
        print_colored "$COLOR_RED" "${name}: cannot read CFBundleExecutable"; return 1; }
    exe="$app/Contents/MacOS/$exe_name"

    # `file` rather than `lipo`: lipo needs the command line tools on a fresh Mac.
    if ! file "$exe" | grep -q 'x86_64'; then
        print_colored "$COLOR_RED" "${name}: the build has no x86_64 slice; refusing to install"
        return 1
    fi
    if ! codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
        print_colored "$COLOR_RED" "${name}: code signature is invalid"
        return 1
    fi
    spctl_out=$(spctl -a -t exec -vv "$app" 2>&1 || true)
    if ! grep -q 'Notarized Developer ID' <<<"$spctl_out"; then
        print_colored "$COLOR_RED" "${name}: Gatekeeper does not report a notarized Developer ID build:"
        printf "%s\n" "$spctl_out"
        return 1
    fi
    team=$(codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    want=$(expected_team_id "$name")
    if [[ -n "$want" && "$team" != "$want" ]]; then
        print_colored "$COLOR_RED" "${name}: Team ID ${team} does not match the expected ${want}"
        return 1
    fi
    print_colored "$COLOR_CYAN" "${name}: signed and notarized (Team ID ${team}$([[ -z "$want" ]] && printf ', not pinned'))"
}

install_cask() {  # install_cask NAME  (cask fields already loaded)
    local name=$1 asset="$TMP_DIR/${1}.asset" staging="$TMP_DIR/${1}.stage" src actual

    print_colored "$COLOR_BRIGHTYELLOW" "${name}: downloading ${C_URL}"
    curl --fail --silent --show-error --location --max-time 600 -o "$asset" "$C_URL"

    actual=$(shasum -a 256 "$asset" | awk '{print $1}')
    if [[ "$actual" != "$C_SHA" ]]; then
        print_colored "$COLOR_RED" "${name}: SHA-256 mismatch (expected ${C_SHA}, got ${actual}); not installing"
        return 1
    fi

    mkdir -p "$staging"
    case "$C_URL" in
        *.dmg)
            MOUNT_POINT="$TMP_DIR/${name}.mnt"
            mkdir -p "$MOUNT_POINT"
            hdiutil attach -nobrowse -readonly -noverify -mountpoint "$MOUNT_POINT" "$asset" >/dev/null
            ditto "$MOUNT_POINT/$C_APP" "$staging/$C_APP"
            hdiutil detach "$MOUNT_POINT" -quiet >/dev/null
            MOUNT_POINT=""
            ;;
        *.zip) ditto -x -k "$asset" "$staging" ;;
        *)
            print_colored "$COLOR_RED" "${name}: unsupported asset type: ${C_URL}"
            return 1
            ;;
    esac
    src="$staging/$C_APP"
    [[ -d "$src" ]] || { print_colored "$COLOR_RED" "${name}: ${C_APP} not found in the download"; return 1; }

    verify_app "$name" "$src" || return 1

    run_cmd rm -rf "${APP_DIR:?}/${C_APP}"
    run_cmd ditto "$src" "${APP_DIR}/${C_APP}"
    record_version "$name" "$C_VERSION"
    print_colored "$COLOR_GREEN" "${name}: installed ${C_VERSION} to ${APP_DIR}"
    cask_caveats "$name"
}

# --- Planning -----------------------------------------------------------------

# Decide, for one cask, what to do. Sets ACTION to install|current|skip and prints a line.
# Supported-OS and up-to-date checks only; selection between yatu and
# openinterminal happens in the caller.
cask_supported() {  # cask_supported NAME -> 0 if the OS can run it (loads the cask)
    load_cask "$1" || return 2
    [[ "$OS_KEY" -ge "$C_MIN_KEY" ]]
}

PLAN_NAMES=""
PLAN_COUNT=0

add_to_plan() {  # add_to_plan NAME ; cask fields for NAME must be loaded; stores a copy
    local name=$1 have
    have=$(installed_version "$name")
    if [[ "$have" == "$C_VERSION" && -d "${APP_DIR}/${C_APP}" ]]; then
        print_colored "$COLOR_CYAN" "${name}: ${C_VERSION} already installed"
        return 0
    fi
    print_colored "$COLOR_GREEN" "${name}: will install ${C_VERSION}${have:+ (have ${have})}"
    PLAN_NAMES="${PLAN_NAMES} ${name}"
    PLAN_COUNT=$((PLAN_COUNT + 1))
}

want_cask() {  # want_cask NAME -> 0 if --only allows it
    [[ -z "$ONLY" || "$ONLY" == "$1" ]]
}

print_colored "$COLOR_CYAN" "macOS ${OS_VERSION} on Intel; reading casks from ${TAP_BASE}"

# Finder terminal button: Yatu where supported, otherwise the OpenInTerminal fork.
finder_choice=""
rc=0; cask_supported yatu || rc=$?
if [[ $rc -eq 2 ]]; then exit 1
elif [[ $rc -eq 0 ]]; then finder_choice=yatu
else
    rc=0; cask_supported openinterminal-lite-inquinity || rc=$?
    if [[ $rc -eq 2 ]]; then exit 1
    elif [[ $rc -eq 0 ]]; then finder_choice=openinterminal-lite-inquinity
    fi
fi

NAMES_TO_CONSIDER=""
if [[ -n "$finder_choice" ]]; then
    NAMES_TO_CONSIDER="$finder_choice"
else
    print_colored "$COLOR_YELLOW" "yatu / openinterminal-lite-inquinity: skipped (macOS ${OS_VERSION} is too old for both)"
fi
NAMES_TO_CONSIDER="${NAMES_TO_CONSIDER} qltextview belvedere"

for name in $NAMES_TO_CONSIDER; do
    want_cask "$name" || continue
    rc=0; cask_supported "$name" || rc=$?
    if [[ $rc -eq 2 ]]; then exit 1
    elif [[ $rc -ne 0 ]]; then
        print_colored "$COLOR_YELLOW" "${name}: skipped (needs macOS ${C_MIN_NAME}, this Mac has ${OS_VERSION})"
        continue
    fi
    add_to_plan "$name"
done

if [[ "$LIST_ONLY" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    exit 0
fi
if [[ "$PLAN_COUNT" -eq 0 ]]; then
    print_colored "$COLOR_GREEN" "Nothing to install."
    exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
    printf "Install%s into %s? Type 'yes' to continue: " "$PLAN_NAMES" "$APP_DIR"
    read -r answer
    [[ "$answer" == "yes" ]] || { print_colored "$COLOR_RED" "Aborted."; exit 1; }
fi

status=0
for name in $PLAN_NAMES; do
    # Reload so the cask fields match this app (the planning pass left the last one).
    load_cask "$name" || { status=1; continue; }
    install_cask "$name" || { print_colored "$COLOR_RED" "${name}: install failed"; status=1; }
done
exit "$status"
