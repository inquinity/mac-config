#!/bin/zsh

# publish-docker-utils.sh - Generate a public docker-utils script from dockerdaemon.sh.
# Usage: publish-docker-utils.sh [output_path]

set -euo pipefail

SOURCE_FILE="${HOME}/mac-config/scripts/dockerdaemon.sh"
OUTPUT_FILE="${1:-${HOME}/dev/GoldenImageCoP/cookbook/scripts/docker-utils.sh}"

if [[ ! -f "${SOURCE_FILE}" ]]; then
  echo "Source file not found: ${SOURCE_FILE}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"

tmp_file="$(mktemp /tmp/docker-utils-XXXX.sh)"
trap 'rm -f "${tmp_file}"' EXIT

# Transform internal dockerd-* helper names to public docker-* helper names.
sed \
  -e 's/dockerdaemon\.sh/docker-utils.sh/g' \
  -e 's/dockerd-/docker-/g' \
  "${SOURCE_FILE}" > "${tmp_file}"

# Basic sanity checks on generated output.
for fn in docker-ls docker-run docker-exec docker-info docker-os docker-sha; do
  if ! rg -q "^${fn}\\(\\)" "${tmp_file}"; then
    echo "Generated file missing function: ${fn}" >&2
    exit 1
  fi
done

if rg -q '^dockerd-' "${tmp_file}"; then
  echo "Generated file still contains dockerd-* function names." >&2
  exit 1
fi

zsh -n "${tmp_file}"
cp "${tmp_file}" "${OUTPUT_FILE}"
chmod 755 "${OUTPUT_FILE}"

echo "Published docker utils:"
echo "  Source: ${SOURCE_FILE}"
echo "  Output: ${OUTPUT_FILE}"
