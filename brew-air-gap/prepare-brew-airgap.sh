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

# Directory where this prepare script itself resides
SOURCEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTDIR="${1:-}"

if [[ -z "$OUTDIR" ]]; then
  echo "Usage: $0 /path/to/output-dir"
  exit 2
fi

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"

echo "Preparing airgap bundle in: $OUTDIR"

# --- Preconditions ------------------------------------------------------------

for cmd in git brew python3 zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd"
    exit 1
  fi
done

HASH_CMD=()

init_hash_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD=(shasum -a 256)
  else
    echo "ERROR: No SHA256 tool found (need sha256sum or shasum)."
    exit 1
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

BREW_CACHE="$(brew --cache)"
BREW_DL_DIR="$BREW_CACHE/downloads"
echo "Homebrew cache: $BREW_CACHE"
echo "Homebrew downloads dir: $BREW_DL_DIR"

mkdir -p "$OUTDIR/homebrew" \
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
cd "$OUTDIR/homebrew"
clone_or_update "https://github.com/Homebrew/brew.git"          "brew.git"
clone_or_update "https://github.com/Homebrew/homebrew-core.git" "homebrew-core.git"
clone_or_update "https://github.com/Homebrew/homebrew-cask.git" "homebrew-cask.git"

# --- portable-ruby fetch + stage ---------------------------------------------

echo
echo "==> Fetching portable-ruby bottles via brew (authoritative)"

BREW_RUNTIME_RUBY="$(brew ruby -e 'puts RUBY_VERSION' 2>/dev/null || true)"
echo "Current installed brew runtime Ruby (informational): ${BREW_RUNTIME_RUBY:-unknown}"

PORTABLE_RUBY_VER="$(brew info --json=v2 portable-ruby | python3 -c '
import sys,json
d=json.load(sys.stdin)
print(d["formulae"][0]["versions"]["stable"])
')"
echo "portable-ruby formula stable version: $PORTABLE_RUBY_VER"

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
echo "Available portable-ruby bottle tags:"
echo "$AVAILABLE_TAGS" | sed 's/^/  - /'

pick_tag() {
  local t
  for t in "$@"; do
    if echo "$AVAILABLE_TAGS" | grep -qx "$t"; then
      echo "$t"
      return 0
    fi
  done
  return 1
}

# Prefer broad-compat tags but only if they exist
INTEL_TAG="$(pick_tag catalina big_sur monterey ventura sonoma sequoia x86_64_big_sur x86_64_monterey x86_64_ventura x86_64_sonoma x86_64_sequoia || true)"
ARM_TAG="$(pick_tag arm64_big_sur arm64_monterey arm64_ventura arm64_sonoma arm64_sequoia || true)"

if [[ -z "${INTEL_TAG:-}" ]]; then
  echo "ERROR: Could not select an Intel bottle tag."
  exit 1
fi
if [[ -z "${ARM_TAG:-}" ]]; then
  echo "ERROR: Could not select an ARM64 bottle tag."
  exit 1
fi

echo "Selected Intel bottle tag: $INTEL_TAG"
echo "Selected ARM64 bottle tag: $ARM_TAG"

echo "Fetching Intel portable-ruby..."
brew fetch -f --bottle-tag="$INTEL_TAG" portable-ruby
echo "Fetching ARM64 portable-ruby..."
brew fetch -f --bottle-tag="$ARM_TAG" portable-ruby

# Locate bottles in either cache root (old layout) or downloads/ (hashed layout)
find_bottle() {
  local tag="$1"

  shopt -s nullglob
  local -a candidates=()

  # Old style (rare now): portable-ruby--X.Y.Z.<tag>.bottle.tar.gz
  candidates+=( "$BREW_CACHE"/portable-ruby--*."$tag".bottle.tar.gz )

  # Hashed downloads style (common):
  # <hash>--portable-ruby--X.Y.Z.<tag>.bottle.tar.gz
  if [[ -d "$BREW_DL_DIR" ]]; then
    candidates+=( "$BREW_DL_DIR"/*--portable-ruby--*."$tag".bottle.tar.gz )
  fi

  shopt -u nullglob

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  # Pick newest by mtime
  local newest="${candidates[0]}"
  local newest_ts
  newest_ts="$(stat -f '%m' "$newest" 2>/dev/null || echo 0)"

  local f ts
  for f in "${candidates[@]}"; do
    ts="$(stat -f '%m' "$f" 2>/dev/null || echo 0)"
    if (( ts > newest_ts )); then
      newest_ts="$ts"
      newest="$f"
    fi
  done

  echo "$newest"
  return 0
}

INTEL_BOTTLE_PATH="$(find_bottle "$INTEL_TAG")" || {
  echo "ERROR: Intel portable-ruby bottle not found for tag '$INTEL_TAG'."
  echo "Searched:"
  echo "  $BREW_CACHE/portable-ruby--*.$INTEL_TAG.bottle.tar.gz"
  echo "  $BREW_DL_DIR/*--portable-ruby--*.$INTEL_TAG.bottle.tar.gz"
  echo "Debug: listing portable-ruby files under downloads/:"
  ls -1 "$BREW_DL_DIR" 2>/dev/null | grep -E 'portable-ruby' || true
  exit 1
}

ARM_BOTTLE_PATH="$(find_bottle "$ARM_TAG")" || {
  echo "ERROR: ARM64 portable-ruby bottle not found for tag '$ARM_TAG'."
  echo "Searched:"
  echo "  $BREW_CACHE/portable-ruby--*.$ARM_TAG.bottle.tar.gz"
  echo "  $BREW_DL_DIR/*--portable-ruby--*.$ARM_TAG.bottle.tar.gz"
  echo "Debug: listing portable-ruby files under downloads/:"
  ls -1 "$BREW_DL_DIR" 2>/dev/null | grep -E 'portable-ruby' || true
  exit 1
}

echo
echo "Located bottles:"
echo "  Intel: $INTEL_BOTTLE_PATH"
echo "  ARM64: $ARM_BOTTLE_PATH"

rm -f "$OUTDIR/ruby/x86_64/"portable-ruby* 2>/dev/null || true
rm -f "$OUTDIR/ruby/arm64/"portable-ruby* 2>/dev/null || true

cp -v "$INTEL_BOTTLE_PATH" "$OUTDIR/ruby/x86_64/"
cp -v "$ARM_BOTTLE_PATH" "$OUTDIR/ruby/arm64/"

echo "Portable-ruby bottles staged:"
ls -lh "$OUTDIR/ruby/x86_64" || true
ls -lh "$OUTDIR/ruby/arm64" || true

# --- README ------------------------------------------------------------------

echo
echo "==> Writing README.txt"
cat > "$OUTDIR/README.txt" <<EOF
Homebrew air-gap bundle
======================

Prepared: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

portable-ruby formula stable version: $PORTABLE_RUBY_VER
Selected bottle tags:
  Intel: $INTEL_TAG
  ARM64: $ARM_TAG

EOF

# --- Copy installer before manifest ------------------------------------------

echo
echo "==> Copying install shell script"
cp -v "$SOURCEDIR/install-brew-airgap.sh" "$OUTDIR/"
chmod 0755 "$OUTDIR/install-brew-airgap.sh"

# --- Manifest ----------------------------------------------------------------

echo
echo "==> Generating SHA256 manifest (may take a while due to large git repos)"
write_manifest "$OUTDIR" "$OUTDIR/manifest.txt"

# --- Zip bundle for easy transfer -------------------------------------------

echo
echo "==> Creating brew-install.zip"
ZIP_NAME="brew-install.zip"
OUTDIR_PARENT="$(dirname "$OUTDIR")"
OUTDIR_BASENAME="$(basename "$OUTDIR")"
(cd "$OUTDIR_PARENT" && rm -f "$ZIP_NAME" && zip -r "$ZIP_NAME" "$OUTDIR_BASENAME")

# --- Completed ----------------------------------------------------------------

echo
echo "Bundle prepared successfully: $OUTDIR"
ls -lah "$OUTDIR"

