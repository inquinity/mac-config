#!/bin/bash
# Speaks a sample phrase in every voice available to `say`, so you can pick one.
set -euo pipefail

say -v '?' | grep 'en_US' | while IFS= read -r line; do
  voice=$(printf '%s\n' "$line" | awk '{print $1}')
  printf '%s\n' "$voice"
  say -v "$voice" "Hi, I'm $voice. This is what I sound like."
done
