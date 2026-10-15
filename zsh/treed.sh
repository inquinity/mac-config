# treed - directory tree listing using find
#
# Usage:
#   treed [ROOT] [--exclude PATTERN]...
#
# Examples:
#
#   # List all directories under the current directory
#   treed
#
#   # List all directories under a specific path
#   treed ~/projects
#
#   # Exclude all .git directories
#   treed --exclude '*/.git'
#
#   # Same idea using recursive-glob-looking syntax
#   # Quote the pattern so zsh does not expand it before treed receives it.
#   treed --exclude '**/.git'
#
#   # Exclude .git directories under a specific root
#   treed ~/projects --exclude '*/.git'
#
#   # Exclude multiple directory types
#   treed \
#     --exclude '*/.git' \
#     --exclude '*/node_modules' \
#     --exclude '*/.venv'
#
#   # Exclude common build/cache directories
#   treed \
#     --exclude '*/.git' \
#     --exclude '*/node_modules' \
#     --exclude '*/dist' \
#     --exclude '*/build' \
#     --exclude '*/target'
#
#   # Python project
#   treed \
#     --exclude '*/.git' \
#     --exclude '*/.venv' \
#     --exclude '*/venv' \
#     --exclude '*/__pycache__'
#
#   # JavaScript / TypeScript project
#   treed \
#     --exclude '*/.git' \
#     --exclude '*/node_modules' \
#     --exclude '*/dist' \
#     --exclude '*/.next'
#
#   # Java / Maven / Gradle project
#   treed \
#     --exclude '*/.git' \
#     --exclude '*/target' \
#     --exclude '*/build' \
#     --exclude '*/.gradle'
#
#   # macOS project, avoiding common metadata/cache dirs
#   treed \
#     --exclude '*/.git' \
#     --exclude '*/.DS_Store' \
#     --exclude '*/DerivedData'
#
#   # Use --exclude=PATTERN form
#   treed --exclude='*/.git'
#
#   # Multiple --exclude= forms
#   treed \
#     --exclude='*/.git' \
#     --exclude='*/node_modules'
#
# Notes:
#
#   - Quote wildcard patterns:
#
#       treed --exclude '*/.git'
#
#     rather than:
#
#       treed --exclude */.git
#
#     Quoting prevents zsh from expanding the glob before treed sees it.
#
#   - For find's -path matching, '*' can match '/' characters, so:
#
#       '*/.git'
#
#     is usually sufficient to match .git directories anywhere below ROOT.
#
#   - Excluded directories are pruned, so find does not descend into them.
#
## 
treed() {
  local root="."
  local -a excludes
  local pattern

  while (( $# )); do
    case "$1" in
      --exclude)
        [[ -n "$2" ]] || {
          echo "treed: --exclude requires a pattern" >&2
          return 1
        }
        excludes+=("$2")
        shift 2
        ;;
      --exclude=*)
        excludes+=("${1#--exclude=}")
        shift
        ;;
      *)
        root="$1"
        shift
        ;;
    esac
  done

  if (( ${#excludes[@]} == 0 )); then
    find "$root" -type d
    return
  fi

  local -a prune_expr

  for pattern in "${excludes[@]}"; do
    (( ${#prune_expr[@]} )) && prune_expr+=(-o)
    prune_expr+=(-path "$pattern")
  done

  find "$root" \( "${prune_expr[@]}" \) -prune -o -type d -print
}
