#!/usr/bin/env bash
set -euo pipefail

# prepare-brew-airgap.sh
#
# Run on an Internet-connected staging Mac.
# Produces a directory bundle you can copy to USB for offline Homebrew bootstrap.
#
# Includes:
#   - Full clones of brew, homebrew-core, homebrew-cask
#   - portable-ruby bottles for BOTH Intel + Apple Silicon fetched via brew
#
# Usage:
#   ./prepare-brew-airgap.sh /path/to/output-dir
#
# Example:
#   ./prepare-brew-airgap.sh "$HOME/brew-air-gap"

OUTDIR="${1:-}"

if [[ -z "$OUTDIR" ]]; then
  echo "Usage: $0 /path/to/output-dir"
  exit 2
fi

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"

echo "Preparing airgap bundle in: $OUTDIR"

# --- Preconditions ------------------------------------------------------------

for cmd in git brew python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd"
    exit 1
  fi
done

BREW_CACHE="$(brew --cache)"
BREW_DL_DIR="$BREW_CACHE/downloads"
echo "Homebrew cache: $BREW_CACHE"
echo "Homebrew downloads dir: $BREW_DL_DIR"

mkdir -p "$OUTDIR/repos" \
         "$OUTDIR/homebrew" \
         "$OUTDIR/ruby/arm64" \
         "$OUTDIR/ruby/x86_64"

# --- Clone Homebrew repos (FULL clones; no --depth) ---------------------------

clone_or_update() {
  local url="$1"
  local dir="$2"

  if [[ -d "$dir/.git" ]]; then
    echo "Repo exists: $dir"
    echo "  Updating (git fetch --all --prune)..."
    git -C "$dir" fetch --all --prune
  else
    echo "Cloning $url -> $dir"
    git clone "$url" "$dir"
  fi
}

echo
echo "==> Cloning/updating Homebrew repositories (full history)"
cd "$OUTDIR/repos"
clone_or_update "https://github.com/Homebrew/brew.git"          "brew.git"
clone_or_update "https://github.com/Homebrew/homebrew-core.git" "homebrew-core.git"
clone_or_update "https://github.com/Homebrew/homebrew-cask.git" "homebrew-cask.git"

echo
echo "==> Copying repos into bundle homebrew/ directory"
rm -rf "$OUTDIR/homebrew/brew.git" "$OUTDIR/homebrew/homebrew-core.git" "$OUTDIR/homebrew/homebrew-cask.git"
cp -a "$OUTDIR/repos/brew.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-core.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-cask.git" "$OUTDIR/homebrew/"

# --- portable-ruby fetch + stage ---------------------------------------------

echo
echo "==> Fetching portable-ruby bottles via brew (authoritative)"

BREW_RUNTIME_RUBY="$(brew ruby -e 'puts RUBY_VERSION' 2>/dev/null || true)"
echo "Current install
