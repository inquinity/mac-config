#!/usr/bin/env bash
set -euo pipefail

# install-brew-airgap.sh
#
# Offline Homebrew bootstrap installer.
#
# Assumptions:
# - This script resides in the TOP directory of the bundle (next to README.txt).
# - Target Mac has Xcode Command Line Tools installed (script will verify only).
# - Bundle contains:
#     homebrew/brew.git
#     homebrew/homebrew-core.git
#     homebrew/homebrew-cask.git   (optional but recommended)
#     ruby/arm64/ (portable-ruby bottle tarball)
#     ruby/x86_64/ (portable-ruby bottle tarball)
#
# Usage:
#   chmod u+x ./install-brew-airgap.sh
#   ./install-brew-airgap.sh            # normal install
#   ./install-brew-airgap.sh --debug    # verbose diagnostics
#   ./install-brew-airgap.sh --verify   # verify manifest.txt (if present)
#
# Logging:
# - Always writes install_log.txt in the bundle root (same directory as this script).
# - Console shows high-level progress; --debug adds more console detail and traces.

# ---------------------------- arg parsing -------------------------------------

DEBUG=0
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --debug)  DEBUG=1 ;;
    --verify) VERIFY=1 ;;
    -h|--help)
      sed -n '1,60p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      echo "Use --help for usage."
      exit 2
      ;;
  esac
done

# ----------------------------- logging ----------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install_log.txt"

timestamp() { date +"%Y-%m-%d %H:%M:%S %z"; }

# Log everything (stdout+stderr) to file; keep console output too.
# This keeps it simple: everything you see on screen is also in the log.
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================================="
echo "Homebrew air-gap install starting: $(timestamp)"
echo "Bundle root: $SCRIPT_DIR"
echo "Log file: $LOG_FILE"
echo "Args: ${*:-<none>}"
echo "============================================================================="

if [[ $DEBUG -eq 1 ]]; then
  echo "[DEBUG] Enabled. Extra command traces will be written to the log file only."
fi

# ----------------------------- helpers ----------------------------------------

die() {
  local msg="$1"
  echo "ERROR: $msg"
  echo "See log: $LOG_FILE"
  exit 1
}

note() {
  echo "==> $*"
}

run_cmd() {
  if [[ $DEBUG -eq 1 ]]; then
    {
      printf '[CMD] '
      printf '%q ' "$@"
      printf '\n'
    } >> "$LOG_FILE"
  fi
  "$@"
}

log_fs_info() {
  local path="$1"
  local parent
  parent="$(dirname "$path")"
  {
    echo "----- Filesystem info -----"
    echo "Target path: $path"
    echo "Parent path: $parent"
    echo "df -h $parent:"
    df -h "$parent" 2>/dev/null || echo "  (df failed)"
    echo "stat -f for $parent:"
    stat -f '%N %H/%L %u:%g %Sp %Sf (%T)' "$parent" 2>/dev/null || echo "  (stat failed)"
    echo "ls -ldO $path:"
    ls -ldO "$path" 2>/dev/null || echo "  (ls failed)"
    echo "ls -ldO $parent:"
    ls -ldO "$parent" 2>/dev/null || echo "  (ls failed)"
    echo "mount entries (root and target parent):"
    mount | awk -v p="$parent" '$0 ~ " on / " || $0 ~ " on "p" " {print "  "$0}'
    echo "---------------------------"
  } >> "$LOG_FILE"
}

init_hash_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD=(shasum -a 256)
  else
    die "No SHA256 tool found (need sha256sum or shasum)."
  fi
}

write_manifest() {
  local base_dir="$1"
  local out_file="$2"
  init_hash_cmd
  (
    cd "$base_dir"
    find . -type f \
      ! -name 'manifest.txt' \
      ! -name 'install_log.txt' \
      -print | LC_ALL=C sort | while IFS= read -r f; do
        "${HASH_CMD[@]}" "$f"
      done
  ) > "$out_file"
}

show_context() {
  echo "----- Context -----"
  echo "Time: $(timestamp)"
  echo "User: $(id)"
  echo "PWD:  $(pwd)"
  echo "umask: $(umask)"
  echo "uname: $(uname -a)"
  echo "sw_vers: $(sw_vers 2>/dev/null || echo 'unavailable')"
  echo "PATH: $PATH"
  echo "-------------------"
}

require_dir() {
  local d="$1"
  [[ -d "$d" ]] || die "Required directory missing: $d"
}

require_file() {
  local f="$1"
  [[ -f "$f" ]] || die "Required file missing: $f"
}

# ----------------------------- preflight --------------------------------------

show_context

# 1) Verify Xcode Command Line Tools (do not install)
note "Checking for Xcode Command Line Tools..."
if ! xcode-select -p >/dev/null 2>&1; then
  cat <<'EOF'
ERROR: Xcode Command Line Tools are NOT installed on this machine.
This installer will not install them.

Required action:
  - Run: xcode-select --install
  - Or download from Apple Developer Downloads:
    https://developer.apple.com/download/all/  (requires Apple ID)

Exiting.
EOF
  exit 1
fi
echo "Xcode Command Line Tools found."

# 2) Verify bundle structure
note "Validating bundle structure..."
require_dir "$SCRIPT_DIR/homebrew"
require_dir "$SCRIPT_DIR/homebrew/brew.git"
require_dir "$SCRIPT_DIR/homebrew/homebrew-core.git"
# cask optional
if [[ -d "$SCRIPT_DIR/homebrew/homebrew-cask.git" ]]; then
  echo "Found homebrew-cask.git"
else
  echo "WARNING: homebrew-cask.git not found; casks will not be available unless added later."
fi

# 3) Architecture + install prefix
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"
  RUBY_ARCH_DIR="arm64"
else
  BREW_PREFIX="/usr/local"
  RUBY_ARCH_DIR="x86_64"
fi

echo "Target architecture: $ARCH"
echo "Homebrew will be installed to: $BREW_PREFIX"

log_fs_info "$BREW_PREFIX"

# 4) Optional manifest verification
if [[ $VERIFY -eq 1 ]]; then
  note "Verification requested (--verify)."
  if [[ -f "$SCRIPT_DIR/manifest.txt" ]]; then
    note "Verifying manifest.txt checksums (this may take a while)..."
    TMPMAN="$(mktemp)"
    write_manifest "$SCRIPT_DIR" "$TMPMAN"
    if ! cmp -s "$TMPMAN" "$SCRIPT_DIR/manifest.txt"; then
      rm -f "$TMPMAN"
      die "Manifest checksum mismatch. Bundle may be corrupted/modified."
    fi
    rm -f "$TMPMAN"
    echo "Manifest OK."
  else
    echo "WARNING: --verify was requested but manifest.txt not found. Skipping."
  fi
else
  echo "Manifest verification disabled (use --verify to enable)."
fi

# 5) Privilege check (inform user clearly)
note "Checking required permissions..."
NEEDS_SUDO=0
if [[ ! -d "$BREW_PREFIX" ]]; then
  parent="$(dirname "$BREW_PREFIX")"
  [[ -w "$parent" ]] || NEEDS_SUDO=1
else
  [[ -w "$BREW_PREFIX" ]] || NEEDS_SUDO=1
fi

if [[ $NEEDS_SUDO -eq 1 ]]; then
  cat <<EOF
NOTE: Installing Homebrew to $BREW_PREFIX requires elevated privileges (sudo).
Please re-run with:

  sudo "$SCRIPT_DIR/install-brew-airgap.sh" ${DEBUG:+--debug} ${VERIFY:+--verify}

Exiting without making changes.
EOF
  exit 3
fi

# ----------------------------- install ----------------------------------------

note "Installing Homebrew files to $BREW_PREFIX..."

# Ensure prefix exists
run_cmd mkdir -p "$BREW_PREFIX"

# Create required directory structure BEFORE copying taps (fix for your cp error)
# brew repo goes to: $BREW_PREFIX/Homebrew
# taps go to:      $BREW_PREFIX/Homebrew/Library/Taps/homebrew/{homebrew-core,homebrew-cask}
run_cmd mkdir -p "$BREW_PREFIX/Homebrew"
run_cmd mkdir -p "$BREW_PREFIX/Homebrew/Library/Taps/homebrew"

# Copy repos (use rsync if available for better progress; else cp -a)
copy_tree() {
  local src="$1"
  local dst="$2"
  if command -v rsync >/dev/null 2>&1; then
    run_cmd rsync -a --delete "$src"/ "$dst"/
  else
    run_cmd rm -rf "$dst"
    run_cmd mkdir -p "$(dirname "$dst")"
    run_cmd cp -a "$src" "$dst"
  fi
}

note "Copying brew.git into $BREW_PREFIX/Homebrew ..."
copy_tree "$SCRIPT_DIR/homebrew/brew.git" "$BREW_PREFIX/Homebrew"

note "Copying homebrew-core.git tap ..."
copy_tree "$SCRIPT_DIR/homebrew/homebrew-core.git" \
  "$BREW_PREFIX/Homebrew/Library/Taps/homebrew/homebrew-core"

if [[ -d "$SCRIPT_DIR/homebrew/homebrew-cask.git" ]]; then
  note "Copying homebrew-cask.git tap ..."
  copy_tree "$SCRIPT_DIR/homebrew/homebrew-cask.git" \
    "$BREW_PREFIX/Homebrew/Library/Taps/homebrew/homebrew-cask"
fi

# Install portable Ruby bottle for this architecture
note "Staging portable Ruby for $ARCH ..."
RUBY_SRC_DIR="$SCRIPT_DIR/ruby/$RUBY_ARCH_DIR"
require_dir "$RUBY_SRC_DIR"

shopt -s nullglob
RUBY_TARS=( "$RUBY_SRC_DIR"/*.bottle.tar.gz "$RUBY_SRC_DIR"/*.tar.gz "$RUBY_SRC_DIR"/*.tgz )
shopt -u nullglob

if [[ ${#RUBY_TARS[@]} -eq 0 ]]; then
  die "No portable-ruby tarball found in $RUBY_SRC_DIR"
fi

RUBY_TAR="${RUBY_TARS[0]}"
echo "Using portable Ruby tarball: $RUBY_TAR"

VENDOR_DIR="$BREW_PREFIX/Homebrew/Library/Homebrew/vendor"
run_cmd mkdir -p "$VENDOR_DIR"
run_cmd tar -xzf "$RUBY_TAR" -C "$VENDOR_DIR"

# Create brew symlink
note "Linking brew into $BREW_PREFIX/bin ..."
run_cmd mkdir -p "$BREW_PREFIX/bin"
[[ -f "$BREW_PREFIX/Homebrew/bin/brew" ]] || die "brew binary not found at $BREW_PREFIX/Homebrew/bin/brew"
run_cmd ln -sf "$BREW_PREFIX/Homebrew/bin/brew" "$BREW_PREFIX/bin/brew"

# Ownership: Homebrew expects user-owned prefix
note "Ensuring $BREW_PREFIX is owned by the invoking user (Homebrew expects user-writeable prefix)..."
OWNER="${SUDO_USER:-$(whoami)}"
if [[ "$OWNER" == "root" ]]; then
  die "Refusing to chown $BREW_PREFIX to root. Re-run with sudo from your user account."
fi
OWNER_GROUP="$(id -gn "$OWNER")"
run_cmd chown -R "$OWNER":"$OWNER_GROUP" "$BREW_PREFIX"

# ----------------------------- postflight -------------------------------------

note "Post-install summary"
echo
echo "Homebrew installed offline to: $BREW_PREFIX"
echo "Add to your shell environment:"
echo "  eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
echo
echo "Quick checks:"
echo "  $BREW_PREFIX/bin/brew --version"
echo "  $BREW_PREFIX/bin/brew doctor"
echo
echo "Recommended environment (optional):"
echo "  export HOMEBREW_NO_AUTO_UPDATE=1"
echo "  export HOMEBREW_NO_ANALYTICS=1"
echo
echo "Log saved to: $LOG_FILE"
echo "Completed: $(timestamp)"
echo "============================================================================="
