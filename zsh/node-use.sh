# Node version switcher (Homebrew-based, not a nvm-style manager).
# Discovers installed node / node@NN formulae at runtime, so it adapts
# automatically as majors are added/removed -- no hardcoded version list.

node-list() {
  local f ver
  brew list --formula 2>/dev/null | grep -E '^node(@[0-9]+)?$' | while read -r f; do
    ver=$(brew list --versions "$f" | awk '{print $2}')
    printf '%s  (%s)\n' "$f" "$ver"
  done
}

node-use() {
  local requested="$1" f target major

  if [[ -z "$requested" ]]; then
    node-list
    return
  fi

  local -a formulae
  formulae=(${(f)"$(brew list --formula 2>/dev/null | grep -E '^node(@[0-9]+)?$')"})

  if [[ ${#formulae[@]} -eq 0 ]]; then
    echo "No node formulae installed via brew." >&2
    return 1
  fi

  if [[ "$requested" == "latest" ]]; then
    # Pick the highest installed major across node and node@NN.
    local best_major=-1 best_formula=""
    for f in $formulae; do
      major="${$(brew list --versions "$f" | awk '{print $2}')%%.*}"
      if (( major > best_major )); then
        best_major=$major
        best_formula=$f
      fi
    done
    target="$best_formula"
  else
    # Prefer an explicit node@<requested> formula.
    for f in $formulae; do
      [[ "$f" == "node@${requested}" ]] && target="$f"
    done

    # Fall back to plain "node" if its major matches what was requested
    # (the unversioned formula always tracks the current stable major).
    if [[ -z "$target" ]] && (( ${formulae[(Ie)node]} )); then
      major="${$(brew list --versions node | awk '{print $2}')%%.*}"
      [[ "$major" == "$requested" ]] && target="node"
    fi
  fi

  if [[ -z "$target" ]]; then
    echo "node@${requested} is not installed." >&2
    node-list
    return 1
  fi

  # Only unlink once we know the target actually exists and is installed.
  for f in $formulae; do
    [[ "$f" != "$target" ]] && brew unlink "$f" >/dev/null 2>&1
  done
  brew link --overwrite "$target"
  node --version
}
