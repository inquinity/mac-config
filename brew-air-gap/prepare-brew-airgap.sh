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

# 2) Detect portable ruby version used by Homebrew
cd "$OUTDIR/repos/brew.git"
echo "Detecting portable Ruby version used by Homebrew..."
# Try a couple of likely places for the variable name.
PORTABLE_RUBY_VERSION="$(grep -RhoE 'PORTABLE_RUBY_VERSION[[:space:]]*=[[:space:]]*\"[^\"]+\"' Library || true)"
if [[ -n "$PORTABLE_RUBY_VERSION" ]]; then
  PORTABLE_RUBY_VERSION="$(echo "$PORTABLE_RUBY_VERSION" | head -n1 | sed -E 's/.*=\"([^\"]+)\".*/\1/')"
fi

# fallback: try to find vendor/portable-ruby version hints
if [[ -z "${PORTABLE_RUBY_VERSION:-}" ]]; then
  # look for vendor/portable-ruby elsewhere
  prfile="$(grep -Rho 'portable-ruby-[0-9]+\.[0-9]+\.[0-9]+' Library || true)"
  if [[ -n "$prfile" ]]; then
    PORTABLE_RUBY_VERSION="$(echo "$prfile" | head -n1 | sed -E 's/.*portable-ruby-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  fi
fi

if [[ -z "${PORTABLE_RUBY_VERSION:-}" ]]; then
  echo "WARNING: Could not auto-detect PORTABLE_RUBY_VERSION in the cloned brew repo."
  echo "You will need to download portable Ruby tarballs manually and place them in the 'ruby' directory."
  echo "Continuing; script will still build the bundle with repos."
else
  echo "Detected portable Ruby version: $PORTABLE_RUBY_VERSION"
fi

# 3) Attempt to download portable Ruby builds for both architectures
# We'll try several filename patterns (Homebrew uses OS-tagged bottles like *_big_sur.bottle.tar.gz).
mkdir -p "$OUTDIR/ruby/arm64" "$OUTDIR/ruby/x86_64"

download_if_exists() {
  url="$1"
  out="$2"
  if curl -sfSL -o "$out" "$url"; then
    echo "Downloaded: $url -> $out"
    return 0
  else
    rm -f "$out" 2>/dev/null || true
    return 1
  fi
}

if [[ -n "${PORTABLE_RUBY_VERSION:-}" ]]; then
  PVER="$PORTABLE_RUBY_VERSION"
  ARCH_PATTERNS=(
    "arm64_big_sur" "arm64_monterey" "arm64_ventura" "arm64_catalina"
    "x86_64_big_sur" "x86_64_monterey" "x86_64_ventura" "x86_64_catalina"
    "arm64" "x86_64"
  )
  BASE_URL="https://github.com/Homebrew/homebrew-portable-ruby/releases/download/portable-ruby-${PVER}"
  for arch in arm64 x86_64; do
    found=0
    for pat in "${ARCH_PATTERNS[@]}"; do
      # build a candidate filename set
      candidates=(
        "portable-ruby-${PVER}.${pat}.bottle.tar.gz"
        "portable-ruby-${PVER}.${pat}.tar.gz"
        "portable-ruby-${PVER}.${pat}.bottle.tar"
        "portable-ruby-${PVER}.${pat}.tgz"
        "portable-ruby-${PVER}.${pat}.zip"
        "portable-ruby-${PVER}.${arch}.bottle.tar.gz"
        "portable-ruby-${PVER}.${arch}.tar.gz"
        "portable-ruby-${PVER}.tar.gz"
      )
      for fname in "${candidates[@]}"; do
        url="${BASE_URL}/${fname}"
        outpath="$OUTDIR/ruby/${arch}/${fname}"
        if download_if_exists "$url" "$outpath"; then
          found=1
          break 2
        fi
      done
    done
    if [[ $found -eq 0 ]]; then
      echo "Could not auto-download portable Ruby for arch $arch. Please download the correct tarball(s) for version $PVER and place them in:"
      echo "  $OUTDIR/ruby/$arch/"
    fi
  done
else
  echo "Skipping portable Ruby auto-download (no version detected). Place portable Ruby tarballs manually in $OUTDIR/ruby/<arch>/"
fi

# 4) Optionally copy Command Line Tools pkg into the bundle
if [[ -n "$CLT_PKG" && -f "$CLT_PKG" ]]; then
  mkdir -p "$OUTDIR/clt"
  cp -v "$CLT_PKG" "$OUTDIR/clt/CommandLineTools.pkg"
  echo "Copied CommandLineTools.pkg into $OUTDIR/clt/"
else
  echo "No CommandLineTools.pkg given. (You said targets already have CLT installed.)"
fi

# 5) Copy the repos into a top-level homebrew dir for copying to USB
mkdir -p "$OUTDIR/homebrew"
cp -a "$OUTDIR/repos/brew.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-core.git" "$OUTDIR/homebrew/"
cp -a "$OUTDIR/repos/homebrew-cask.git" "$OUTDIR/homebrew/"

# 6) Create a README and manifest of checksums
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
