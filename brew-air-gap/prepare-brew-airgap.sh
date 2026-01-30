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

# 2)  ruby ...
echo "Portable Ruby handling:"
echo "  This bundle does NOT auto-download portable Ruby."
echo "  You must manually place portable Ruby tarballs here:"
echo "    ruby/arm64/"
echo "    ruby/x86_64/"
echo
echo "Expected filenames look like:"
echo "  portable-ruby-<version>.arm64_big_sur.bottle.tar.gz"
echo "  portable-ruby-<version>.x86_64_big_sur.bottle.tar.gz"
echo
brew ruby -e 'puts RUBY_VERSION'

chrome https://github.com/Homebrew/homebrew-portable-ruby/releases

# Wait for any single keypress (no Enter needed)
read -n 1 -s -r -p "Press any key to continue..."

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
