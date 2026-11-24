#!/bin/bash
#
# Offline tests for install-tools.sh: fixture casks served over file://, a temp
# /Applications, and a temp state file. Never touches the network or the real
# /Applications. Covers OS selection, interpolation, the up-to-date skip, and
# that a SHA-256 mismatch installs nothing.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/install-tools.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/intel-tools-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

mkdir -p "$WORK/Casks" "$WORK/apps" "$WORK/assets"
printf 'not really a zip\n' > "$WORK/assets/Tool-1.0.zip"

write_cask() {  # write_cask NAME MIN_SYMBOL
    cat > "$WORK/Casks/$1.rb" <<EOF
cask "$1" do
  version "1.0"
  sha256 "$(printf '0%.0s' $(seq 1 64))"
  url "file://$WORK/assets/Tool-#{version}.zip"
  app "Tool.app"
  depends_on macos: :$2
end
EOF
}
write_cask yatu ventura
write_cask openinterminal-lite-inquinity monterey
write_cask qltextview tahoe
write_cask belvedere tahoe

run() {  # run MACOS_VERSION [args...]
    local v=$1; shift
    INTEL_TOOLS_ALLOW_ARM64=1 INTEL_TOOLS_MACOS_VERSION="$v" \
    INTEL_TOOLS_TAP_BASE="file://$WORK/Casks" INTEL_TOOLS_APP_DIR="$WORK/apps" \
    INTEL_TOOLS_STATE_FILE="$WORK/state" "$SCRIPT" "$@" 2>&1
}

out=$(run 26.0 --list)
grep -q 'yatu: will install 1.0' <<<"$out" && grep -q 'belvedere: will install' <<<"$out" \
    && ! grep -q 'openinterminal' <<<"$out" \
    && pass "macOS 26 picks yatu, qltextview and belvedere" || fail "macOS 26 selection"

out=$(run 13.7 --list)
grep -q 'yatu: will install' <<<"$out" && grep -q 'belvedere: skipped' <<<"$out" \
    && pass "macOS 13 picks yatu and skips Tahoe-only tools" || fail "macOS 13 selection"

out=$(run 12.7 --list)
grep -q 'openinterminal-lite-inquinity: will install' <<<"$out" && ! grep -q 'yatu: will' <<<"$out" \
    && pass "macOS 12 falls back to openinterminal" || fail "macOS 12 selection"

out=$(run 11.7 --list)
grep -q 'too old for both' <<<"$out" \
    && pass "macOS 11 skips the Finder button entirely" || fail "macOS 11 selection"

out=$(run 10.15.7 --list)
grep -q 'too old for both' <<<"$out" \
    && pass "macOS 10.15 compares below 12" || fail "macOS 10.15 selection"

printf 'yatu 1.0\n' > "$WORK/state"; mkdir -p "$WORK/apps/Tool.app"
out=$(run 13.7 --list)
grep -q 'yatu: 1.0 already installed' <<<"$out" \
    && pass "up-to-date app is skipped" || fail "up-to-date skip"
rm -f "$WORK/state"; rmdir "$WORK/apps/Tool.app"

if out=$(run 13.7 --yes --only yatu); then
    fail "SHA mismatch should exit non-zero"
elif grep -q 'SHA-256 mismatch' <<<"$out" && [[ -z "$(ls -A "$WORK/apps")" && ! -f "$WORK/state" ]]; then
    pass "SHA mismatch installs nothing and records nothing"
else
    fail "SHA mismatch handling: $out"
fi

out=$(run 13.7 --dry-run)
[[ -z "$(ls -A "$WORK/apps")" ]] && pass "--dry-run installs nothing" || fail "--dry-run"

if INTEL_TOOLS_TAP_BASE="file://$WORK/nope" INTEL_TOOLS_ALLOW_ARM64=1 INTEL_TOOLS_MACOS_VERSION=13.0 "$SCRIPT" --list >/dev/null 2>&1; then
    fail "unreachable tap should fail"
else
    pass "unreachable tap fails instead of installing nothing silently"
fi

[[ "$FAILURES" -eq 0 ]] && { printf 'All tests passed.\n'; exit 0; }
printf '%d test(s) failed.\n' "$FAILURES"; exit 1
