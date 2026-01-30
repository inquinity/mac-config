#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo? ./install-brew-airgap.sh /path/to/mounted-bundle
# Example:
#   ./install-brew-airgap.sh /Volumes/BREW-AIRGAP/brew-airgap

BUNDLE_ROOT="${1:-}"
if [[ -z "$BUNDLE_ROOT" ]]; then
  echo "Usage: $0 /path/to/bundle-root"
  exit 2
fi

BUNDLE_ROOT="$(cd "$BUNDLE_ROOT" && pwd)"
echo "Using bundle at: $BUNDLE_ROOT"

# 1) Check for Xcode Command Line Tools (DO NOT attempt to install)
if ! xcode-select -p >/dev/null 2>&1; then
  cat <<EOF
ERROR: Xcode Command Line Tools are NOT installed on this machine.
This script will not attempt to install them.
You MUST install them before proceeding.

Apple guidance:
  Open Terminal and run: xcode-select --install
or download the pkg from:
  https://developer.apple.com/download/all/  (requires Apple ID)

Exiting.
EOF
  exit 1
fi
echo "Xcode Command Line Tools found."

# 2) Check for basic tools
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is not available. Command Line Tools should have provided git. Aborting."
  exit 1
fi

# 3) Determine target architecture and preferred brew prefix
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

# 4) Check write permission to BREW_PREFIX (we will need to create directories and chown)
NEEDS_SUDO=0
if [[ ! -d "$BREW_PREFIX" ]]; then
  # check if parent is writable
  parent="$(dirname "$BREW_PREFIX")"
  if [[ ! -w "$parent" ]]; then
    NEEDS_SUDO=1
  fi
else
  if [[ ! -w "$BREW_PREFIX" ]]; then
    NEEDS_SUDO=1
  fi
fi

if [[ $NEEDS_SUDO -eq 1 ]]; then
  echo
  echo "NOTE: Installing Homebrew to $BREW_PREFIX requires elevated privileges (sudo)."
  echo "Please re-run this script with sudo, or ensure you have permissions to write to $BREW_PREFIX."
  echo "Example: sudo $0 $BUNDLE_ROOT"
  exit 3
fi

# 5) Verify bundle expected files exist
if [[ ! -d "$BUNDLE_ROOT/homebrew/brew.git" ]]; then
  echo "ERROR: bundle missing homebrew/brew.git directory."
  exit 1
fi
if [[ ! -d "$BUNDLE_ROOT/homebrew/homebrew-core.git" ]]; then
  echo "ERROR: bundle missing homebrew/homebrew-core.git directory."
  exit 1
fi
if [[ ! -d "$BUNDLE_ROOT/homebrew/homebrew-cask.git" ]]; then
  echo "WARNING: homebrew-cask.git not found — continue if you intentionally excluded cask."
fi

# 6) Verify manifest checksums if present
if [[ -f "$BUNDLE_ROOT/manifest.txt" ]]; then
  echo "Verifying manifest checksums..."
  # compute local sha256s and compare
  # We will reproduce the same ordering and format produced by prepare script: sha256sum <file>
  TMPMAN="$(mktemp)"
  (cd "$BUNDLE_ROOT" && find . -type f -print0 | sort -z | xargs -0 sh -c 'for f; do sha256sum "$f"; done' sh) > "$TMPMAN"
  if ! cmp -s "$TMPMAN" "$BUNDLE_ROOT/manifest.txt"; then
    echo "ERROR: manifest checksum mismatch. The bundle may be corrupted or modified."
    echo "You may want to re-copy the bundle to the USB or re-run integrity checks on the staging machine."
    rm -f "$TMPMAN"
    exit 1
  fi
  rm -f "$TMPMAN"
  echo "Manifest OK."
else
  echo "No manifest.txt found in bundle — skipping checksum verification."
fi

# 7) Copy Homebrew repositories
echo "Installing Homebrew files to $BREW_PREFIX..."
mkdir -p "$BREW_PREFIX"
# ensure directory ownership change is acceptable to current user
echo "Copying repos (this may take a while)..."
cp -a "$BUNDLE_ROOT/homebrew/brew.git" "$BREW_PREFIX/Homebrew"
cp -a "$BUNDLE_ROOT/homebrew/homebrew-core.git" "$BREW_PREFIX/Homebrew/Library/Taps/homebrew/homebrew-core"
if [[ -d "$BUNDLE_ROOT/homebrew/homebrew-cask.git" ]]; then
  mkdir -p "$BREW_PREFIX/Homebrew/Library/Taps/homebrew"
  cp -a "$BUNDLE_ROOT/homebrew/homebrew-cask.git" "$BREW_PREFIX/Homebrew/Library/Taps/homebrew/homebrew-cask"
fi

# 8) Extract portable Ruby for this architecture into Homebrew vendor path
VENDOR_DIR="$BREW_PREFIX/Homebrew/Library/Homebrew/vendor"
mkdir -p "$VENDOR_DIR"
RUBY_SRC_DIR="$BUNDLE_ROOT/ruby/$RUBY_ARCH_DIR"
if [[ -d "$RUBY_SRC_DIR" ]]; then
  # pick the first tarball matching portable-ruby*.tar.gz
  shopt -s nullglob
  TAR_CAND=("$RUBY_SRC_DIR"/portable-ruby*.tar.gz "$RUBY_SRC_DIR"/*.tar.gz "$RUBY_SRC_DIR"/*.tgz)
  if [[ ${#TAR_CAND[@]} -eq 0 ]]; then
    echo "WARNING: No portable Ruby tarball found for $RUBY_ARCH_DIR in $RUBY_SRC_DIR."
    echo "If Homebrew requires a portable Ruby, it may fail until you put the correct tarball there."
  else
    TAR="${TAR_CAND[0]}"
    echo "Extracting portable Ruby from $TAR ..."
    tar -xzf "$TAR" -C "$VENDOR_DIR"
    echo "Portable Ruby extracted."
  fi
  shopt -u nullglob
else
  echo "No ruby directory found for $RUBY_ARCH_DIR. Skipping portable Ruby extraction."
fi

# 9) Create brew symlink in prefix/bin
mkdir -p "$BREW_PREFIX/bin"
if [[ -f "$BREW_PREFIX/Homebrew/bin/brew" ]]; then
  ln -sf "$BREW_PREFIX/Homebrew/bin/brew" "$BREW_PREFIX/bin/brew"
  echo "Linked $BREW_PREFIX/bin/brew -> $BREW_PREFIX/Homebrew/bin/brew"
else
  echo "ERROR: $BREW_PREFIX/Homebrew/bin/brew not found. Aborting."
  exit 1
fi

# 10) Ensure ownership/perms for brew files (brew expects user writable prefix)
# We will chown prefix to current user (user running script) if safe.
OWNER="$(whoami)"
echo "Setting $BREW_PREFIX ownership to user: $OWNER (Homebrew expects user-owned prefix)."
chown -R "$OWNER" "$BREW_PREFIX"

# 11) Print final instructions and quick tests
echo
echo "Homebrew files installed to $BREW_PREFIX."
echo "To initialize your shell run (copy the correct line for your shell / arch):"
echo
echo "  eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
echo
echo "Then test with:"
echo "  $BREW_PREFIX/bin/brew --version"
echo "  $BREW_PREFIX/bin/brew doctor"
echo
echo "If you plan to disable auto-updates and analytics, you can set:"
echo "  export HOMEBREW_NO_AUTO_UPDATE=1"
echo "  export HOMEBREW_NO_ANALYTICS=1"
echo
echo "If you want Homebrew to fetch bottles from an internal artifact proxy later, set:"
echo "  export HOMEBREW_BOTTLE_DOMAIN=https://your-internal-bottle-proxy.example.com"
echo
echo "WARNING: Some formula operations may still expect remote Git remotes or network access to fetch resources."
echo "You should configure Git remote URLs for Homebrew repos to point to internal mirrors if you run offline:"
echo "  git -C \"$BREW_PREFIX/Homebrew\" remote set-url origin https://internal.example.com/brew.git"
echo
echo "Install complete."
