#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./prepare-brew-airgap.sh /path/to/output-dir [optional: /path/to/CommandLineTools.pkg]
#
# Example:
#   ./prepare-brew-airgap.sh ~/Desktop/brew-airgap ~/Downloads/CommandLineTools.pkg

OUTDIR="${1:-}"
CLT_PKG="${2:-}"

if [[ -z "$OUTDIR" ]]; then
  echo "Usage: $0 /path/to/output-dir [optional: /path/to/CommandLineTools.pkg]"
  exit 2
fi

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
echo "Preparing airgap bundle in: $OUTDIR"

# 1) Clone full repos (no --depth)
cd "$OUTDIR"
mkdir -p repos
cd repos

echo "Cloning Homebrew repositories (full clones). This may take some time..."

if [[ -d brew.git ]]; then
  echo "brew.git already exists — skipping clone (remove to refresh)."
else
  git clone https://github.com/Homebrew/brew.git brew.git
fi

if [[ -d homebrew-core.git ]]; then
  echo "homebrew-core.git already exists — skipping clone (remove to refresh)."
else
  git clone https://github.com/Homebrew/homebrew-core.git homebrew-core.git
fi

if [[ -d homebrew-cask.git ]]; then
  echo "homebrew-cask.git already exists — skipping clone (remove to refresh)."
else
  git clone https://github.com/Homebrew/homebrew-cask.git homebrew-cask.git
fi

+ # 2) Fetch portable Ruby bottles using Homebrew itself (reliable; portable-ruby is now distributed as bottles via GHCR)
+ #
+ # NOTE: This requires Homebrew to be installed and working on the connected staging machine.
+ # It avoids brittle parsing and avoids hand-constructing GHCR URLs.
+ mkdir -p "$OUTDIR/ruby/arm64" "$OUTDIR/ruby/x86_64"
+ 
+ if ! command -v brew >/dev/null 2>&1; then
+   echo "ERROR: Homebrew (brew) is not installed on this connected staging machine."
+   echo "Portable Ruby bottles are best fetched via 'brew fetch' (Homebrew handles registry URLs/auth)."
+   echo "Install Homebrew on the staging machine, then re-run this script."
+   exit 1
+ fi
+ 
+ echo "Detecting Homebrew Ruby version (informational)..."
+ BREW_RUBY_VERSION="$(brew ruby -e 'puts RUBY_VERSION' 2>/dev/null || true)"
+ if [[ -n "${BREW_RUBY_VERSION:-}" ]]; then
+   echo "Homebrew Ruby version reported by brew: $BREW_RUBY_VERSION"
+ else
+   echo "WARNING: Could not read Ruby version via 'brew ruby'. Continuing."
+ fi
+ 
+ BREW_CACHE="$(brew --cache)"
+ echo "Homebrew cache: $BREW_CACHE"
+ 
+ echo "Fetching portable-ruby bottles into the cache..."
+ # Oldest-supported tags (generally) for maximum compatibility:
+ # - Intel: catalina
+ # - Apple Silicon: arm64_big_sur
+ # If your environment uses different minimum macOS versions, change these tags.
+ brew fetch --force-bottle --bottle-tag=catalina portable-ruby
+ brew fetch --force-bottle --bottle-tag=arm64_big_sur portable-ruby
+ 
+ echo "Copying fetched portable-ruby bottle files into the airgap bundle..."
+ shopt -s nullglob
+ INTEL_BOTTLES=( "$BREW_CACHE"/portable-ruby--*.catalina.bottle.tar.gz )
+ ARM_BOTTLES=( "$BREW_CACHE"/portable-ruby--*.arm64_big_sur.bottle.tar.gz )
+ shopt -u nullglob
+ 
+ if [[ ${#INTEL_BOTTLES[@]} -eq 0 ]]; then
+   echo "ERROR: Did not find an Intel portable-ruby bottle in cache matching:"
+   echo "  $BREW_CACHE/portable-ruby--*.catalina.bottle.tar.gz"
+   echo "Check 'brew fetch' output and/or available bottle tags for portable-ruby."
+   exit 1
+ fi
+ if [[ ${#ARM_BOTTLES[@]} -eq 0 ]]; then
+   echo "ERROR: Did not find an ARM portable-ruby bottle in cache matching:"
+   echo "  $BREW_CACHE/portable-ruby--*.arm64_big_sur.bottle.tar.gz"
+   echo "Check 'brew fetch' output and/or available bottle tags for portable-ruby."
+   exit 1
+ fi
+ 
+ cp -v "${INTEL_BOTTLES[0]}" "$OUTDIR/ruby/x86_64/"
+ cp -v "${ARM_BOTTLES[0]}" "$OUTDIR/ruby/arm64/"
+ 
+ echo "Portable Ruby bottles staged:"
+ ls -lh "$OUTDIR/ruby/x86_64" || true
+ ls -lh "$OUTDIR/ruby/arm64" || true

# 3) Copy the repos into a top-level homebrew dir for copying to USB
mkdir -p "$OUTDIR/homebrew"
cp -a "$OUTDIR/repos/brew.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-core.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-cask.git" "$OUTDIR/homebrew/"

# 4) Create a README and manifest of checksums
cat > "$OUTDIR/README.txt" <<'EOF'
Homebrew air-gap bundle
-----------------------
Structure:
  homebrew/
    brew.git/
    homebrew-core.git/
    homebrew-cask.git/
  ruby/
    arm64/
    x86_64/
  clt/
    CommandLineTools.pkg  (optional)
  manifest.txt   (sha256 sums)
  README.txt

On the target mac:
  1) Ensure Xcode Command Line Tools are installed.
  2) Insert USB and run install script (install-brew-airgap.sh) from the bundle root.
EOF

echo "Generating SHA256 manifest..."
cd "$OUTDIR"
# find files but avoid hashing .git/objects huge trees directly? We need to include .git, so hash top-level archives instead.
# We'll produce checksums for the directories by creating tarballs for large directories first, then remove tars to keep bundle small?
# Simpler: produce checksums for everything but .git/object content could be huge and slow.
# We'll compute sha256 for all files (this may take time) — user requested complete bundle.
find . -type f -print0 | sort -z | xargs -0 sh -c 'for f; do sha256sum "$f"; done' sh > "$OUTDIR/manifest.txt" || true

echo "Bundle prepared in: $OUTDIR"
echo "Contents:"
ls -lah "$OUTDIR"

echo "Done. Copy the entire $OUTDIR directory to your USB drive (preserve permissions)."
