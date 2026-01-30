#!/usr/bin/env bash
set -euo pipefail

# prepare-brew-airgap.sh
#
# Run on an Internet-connected Mac (your staging/source machine).
# Produces a directory bundle you can copy to a USB drive and use for offline install.
#
# What it does:
#   - Full-clones Homebrew repos: brew, homebrew-core, homebrew-cask (no shallow clones)
#   - Fetches portable-ruby bottles for BOTH Intel + Apple Silicon using Homebrew itself
#     (portable-ruby bottles are distributed via Homebrew’s bottle infrastructure; do not scrape GitHub releases)
#   - Copies everything into a clean bundle layout
#   - Generates a SHA256 manifest
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

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required on the staging machine."
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew (brew) is required on the staging machine to fetch portable-ruby bottles."
  echo "Install Homebrew on this connected machine and re-run."
  exit 1
fi

# --- Bundle layout ------------------------------------------------------------

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

# Copy repos into the bundle "homebrew/" directory (so you can ship just the bundle)
echo
echo "==> Copying repos into bundle homebrew/ directory"
rm -rf "$OUTDIR/homebrew/brew.git" "$OUTDIR/homebrew/homebrew-core.git" "$OUTDIR/homebrew/homebrew-cask.git"
cp -a "$OUTDIR/repos/brew.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-core.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-cask.git" "$OUTDIR/homebrew/"

# --- Fetch portable-ruby bottles for Intel + ARM via brew ---------------------

echo
echo "==> Fetching portable-ruby bottles via brew (authoritative)"
BREW_CACHE="$(brew --cache)"
echo "Homebrew cache: $BREW_CACHE"

# Informational only: this is the Ruby currently used by *this* brew runtime (may differ from formula version).
BREW_RUNTIME_RUBY="$(brew ruby -e 'puts RUBY_VERSION' 2>/dev/null || true)"
echo "Current installed brew runtime Ruby (informational): ${BREW_RUNTIME_RUBY:-unknown}"

# Read available bottle tags for portable-ruby from Homebrew metadata.
PORTABLE_RUBY_JSON="$(brew info --json=v2 portable-ruby)"
AVAILABLE_TAGS="$(
  printf '%s' "$PORTABLE_RUBY_JSON" | python3 -c '
import sys, json
d=json.load(sys.stdin)
files=d["formulae"][0]["bottle"]["stable"]["files"]
for k in files.keys():
    print(k)
'
)"

if [[ -z "${AVAILABLE_TAGS// }" ]]; then
  echo "ERROR: Could not read available bottle tags for portable-ruby from brew."
  exit 1
fi

echo "Available portable-ruby bottle tags:"
echo "$AVAILABLE_TAGS" | sed 's/^/  - /'

pick_tag() {
  # pick_tag <candidate1> <candidate2> ...
  local t
  for t in "$@"; do
    if echo "$AVAILABLE_TAGS" | grep -qx "$t"; then
      echo "$t"
      return 0
    fi
  done
  return 1
}

# Choose tags that actually exist. Prefer "oldest-ish" for broader compatibility,
# but fall back to whatever Homebrew currently publishes.
#
# Notes:
# - Intel tags are often OS-only (e.g. sonoma/ventura/monterey/big_sur) OR x86_64_* variants.
# - ARM tags are usually arm64_* variants.
INTEL_TAG="$(
  pick_tag \
    catalina big_sur monterey ventura sonoma sequoia \
    x86_64_catalina x86_64_big_sur x86_64_monterey x86_64_ventura x86_64_sonoma x86_64_sequoia \
    || true
)"
ARM_TAG="$(
  pick_tag \
    arm64_big_sur arm64_monterey arm64_ventura arm64_sonoma arm64_sequoia \
    || true
)"

if [[ -z "${INTEL_TAG:-}" ]]; then
  echo "ERROR: Could not find a suitable Intel bottle tag for portable-ruby."
  echo "Available tags were:"
  echo "$AVAILABLE_TAGS" | sed 's/^/  - /'
  echo "Fix: pick an Intel-compatible tag above and hardcode INTEL_TAG in the script."
  exit 1
fi

if [[ -z "${ARM_TAG:-}" ]]; then
  echo "ERROR: Could not find a suitable ARM64 bottle tag for portable-ruby."
  echo "Available tags were:"
  echo "$AVAILABLE_TAGS" | sed 's/^/  - /'
  echo "Fix: pick an arm64_* tag above and hardcode ARM_TAG in the script."
  exit 1
fi

echo "Selected Intel bottle tag: $INTEL_TAG"
echo "Selected ARM64 bottle tag: $ARM_TAG"

# Fetch bottles. Important: DO NOT use --force-bottle with --bottle-tag (mutually exclusive).
echo "Fetching Intel portable-ruby..."
brew fetch -f --bottle-tag="$INTEL_TAG" portable-ruby
echo "Fetching ARM64 portable-ruby..."
brew fetch -f --bottle-tag="$ARM_TAG" portable-ruby

# Copy fetched bottles into bundle.
echo "Copying fetched portable-ruby bottles into bundle ruby/..."
shopt -s nullglob
INTEL_BOTTLES=( "$BREW_CACHE"/portable-ruby--*."$INTEL_TAG".bottle.tar.gz )
ARM_BOTTLES=( "$BREW_CACHE"/portable-ruby--*."$ARM_TAG".bottle.tar.gz )
shopt -u nullglob

if [[ ${#INTEL_BOTTLES[@]} -eq 0 ]]; then
  echo "ERROR: Intel portable-ruby bottle not found in cache after fetch."
  echo "Expected pattern: $BREW_CACHE/portable-ruby--*.$INTEL_TAG.bottle.tar.gz"
  echo "Cache portable-ruby entries:"
  ls -1 "$BREW_CACHE" | grep -E 'portable-ruby--' || true
  exit 1
fi

if [[ ${#ARM_BOTTLES[@]} -eq 0 ]]; then
  echo "ERROR: ARM64 portable-ruby bottle not found in cache after fetch."
  echo "Expected pattern: $BREW_CACHE/portable-ruby--*.$ARM_TAG.bottle.tar.gz"
  echo "Cache portable-ruby entries:"
  ls -1 "$BREW_CACHE" | grep -E 'portable-ruby--' || true
  exit 1
fi

# Clear old copies, then copy the newest match (first match is fine; brew cache typically only has one per tag)
rm -f "$OUTDIR/ruby/x86_64/"portable-ruby--*.bottle.tar.gz 2>/dev/null || true
rm -f "$OUTDIR/ruby/arm64/"portable-ruby--*.bottle.tar.gz 2>/dev/null || true

cp -v "${INTEL_BOTTLES[0]}" "$OUTDIR/ruby/x86_64/"
cp -v "${ARM_BOTTLES[0]}" "$OUTDIR/ruby/arm64/"

echo "Portable-ruby bottles staged:"
ls -lh "$OUTDIR/ruby/x86_64" || true
ls -lh "$OUTDIR/ruby/arm64" || true

# --- Write README -------------------------------------------------------------

echo
echo "==> Writing README.txt"
cat > "$OUTDIR/README.txt" <<EOF
Homebrew air-gap bundle
======================

This bundle was prepared on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Contents:
  homebrew/
    brew.git/
    homebrew-core.git/
    homebrew-cask.git/
  ruby/
    arm64/    (portable-ruby bottle(s))
    x86_64/   (portable-ruby bottle(s))
  manifest.txt (sha256 checksums)
  README.txt

Notes:
- These are FULL git repositories (not shallow).
- portable-ruby bottles were fetched using brew and copied from brew's cache.
- Copy this entire directory to a USB drive preserving permissions (e.g. cp -a or Finder copy).

Portable-ruby bottle tags selected:
  Intel tag: $INTEL_TAG
  ARM tag:   $ARM_TAG

Installed brew runtime Ruby (informational):
  ${BREW_RUNTIME_RUBY:-unknown}

EOF

# --- Generate SHA256 manifest -------------------------------------------------

echo
echo "==> Generating SHA256 manifest (may take a while due to large git repos)"
cd "$OUTDIR"
# This hashes every file (including .git object packs). If that's too slow/huge for you,
# tell me and I'll switch to generating tarballs + hashing the tarballs instead.
find . -type f -print0 | sort -z | xargs -0 sh -c 'for f; do sha256sum "$f"; done' sh > "$OUTDIR/manifest.txt"

echo
echo "Bundle prepared successfully: $OUTDIR"
echo "Top-level contents:"
ls -lah "$OUTDIR"
echo
echo "Next: copy this folder to your USB drive."
