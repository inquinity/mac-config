#!/usr/bin/env zsh
#
# build-emacs-mac.zsh -- build emacs-mac into a staging app bundle.
#
# Expects the sibling layout this script lives in:
#
#   emacs-builds/
#     build-emacs-mac.zsh  this script
#     src-release/         git worktree of the emacs-mac repo (detached HEAD)
#     staging-release/     --enable-mac-app install target
#     logs/                build-release-<timestamp>.log
#
# Intended workflow:
#   1. Update the repository yourself (git fetch / git pull in the main checkout).
#   2. Run this script to check out a ref in src-release and build it.
#   3. Hand-copy staging-release/Emacs.app to /Applications.
#
# The script never writes to /Applications and never calls sudo. It prints the
# copy commands at the end so installing stays a deliberate, manual step.

# Ignore any options inherited from the user's environment, then opt in to the
# strict behaviour this script relies on. PIPE_FAIL matters because the build
# output is piped through tee.
emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output.
# %b expands the escape sequences; %s keeps the message itself out of the
# format string, so a literal % in a path cannot corrupt the output.
print_colored() {
    local color="$1"
    local message="$2"
    printf '%b%s%b\n' "$color" "$message" "$COLOR_RESET"
}

# ---------------------------------------------------------------- globals ---

# :A resolves to an absolute, symlink-free path; :h and :t are dirname/basename.
script_name="${0:A:t}"
builds_root="${0:A:h}"

source_dir="${builds_root}/src-release"
staging_dir="${builds_root}/staging-release"
logs_dir="${builds_root}/logs"
staged_app="${staging_dir}/Emacs.app"
installed_app="/Applications/Emacs.app"

# Homebrew supplies autoconf, automake, makeinfo and gnutls; make sure they are
# reachable even when the script runs from a minimal environment.
if [[ -d /opt/homebrew/bin ]]; then
    path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
fi

# Configure flags. These mirror the documented emacs-mac macOS 27 build.
# Edit this array to change how Emacs is built.
configure_flags=(
    "--enable-mac-app=${staging_dir}"
    --with-mac
    --enable-mac-self-contained
    --with-gnutls
    --without-native-compilation
)
configure_cflags="-O2 -g"

target_ref="origin/emacs-mac-31"
make_jobs="$(sysctl -n hw.ncpu 2>/dev/null || print 4)"

dry_run=0
incremental=0
log_file=""

# ------------------------------------------------------------------- help ---

usage() {
    print_colored "$COLOR_YELLOW" "Usage: ${script_name} [options]

Build emacs-mac from src-release into staging-release, under
${builds_root}.

Options:
  -r, --ref <ref>      Commit, tag or branch to build (default: ${target_ref})
  -j, --jobs <n>       Parallel make jobs (default: ${make_jobs})
  -i, --incremental    Reuse the existing configuration: skip distclean,
                       autogen and configure. Much faster, but will not pick
                       up edits to the configure flags inside this script.
  -n, --dry-run        Print the actions without running them
      --debug          Trace shell execution (set -x)
  -h, --help           Show this help

Update the repository yourself before running this. The finished bundle is
left in staging-release; copying it to ${installed_app} is a manual step and
the script prints the commands for it when the build succeeds."
}

# --------------------------------------------------------------- helpers ---

die() {
    print_colored "$COLOR_RED" "ERROR: $*" >&2
    exit 1
}

# Echo a command, then run it unless --dry-run is in effect.
run_step() {
    print_colored "$COLOR_BRIGHTYELLOW" "==> $*"
    if (( dry_run )); then
        return 0
    fi
    "$@"
}

# Confirm every tool the build needs is on PATH before doing any work.
validate_tools() {
    local missing_tools=()
    local required_tool
    for required_tool in git autoconf automake makeinfo pkg-config make xcrun; do
        (( $+commands[$required_tool] )) || missing_tools+=("$required_tool")
    done
    if (( $#missing_tools )); then
        die "missing required tools: ${missing_tools[*]}
Install them with: brew install autoconf automake texinfo pkg-config gnutls"
    fi
}

validate_layout() {
    [[ -d "$source_dir" ]] \
        || die "build worktree not found: ${source_dir}
Create it from your main checkout with:
  git worktree add --detach ${source_dir} ${target_ref}"
    [[ -x "${source_dir}/autogen.sh" ]] \
        || die "${source_dir} does not look like an Emacs source tree (no autogen.sh)"

    # Refuse to clobber in-progress edits in the build worktree.
    if [[ -n "$(git -C "$source_dir" status --porcelain --untracked-files=no)" ]]; then
        die "${source_dir} has uncommitted tracked changes; commit or discard them first"
    fi
}

# Turn whatever the user passed into a concrete commit SHA, so the build and
# the final report agree even if the ref moves underneath us.
resolve_ref() {
    local resolved
    resolved="$(git -C "$source_dir" rev-parse --verify --quiet "${target_ref}^{commit}" || true)"
    [[ -n "$resolved" ]] \
        || die "cannot resolve '${target_ref}' in ${source_dir}
If it is a new upstream commit, fetch it first:
  git -C ${source_dir} fetch origin"
    print -r -- "$resolved"
}

# The build proper. Kept in one function so the caller can pipe the whole thing
# through tee; when it runs inside that pipeline it is a subshell, so `die`
# ends the build and the status is recovered from $pipestatus.
run_build() {
    local target_commit="$1"

    print_colored "$COLOR_YELLOW" "source:   ${source_dir}
ref:      ${target_ref}
commit:   ${target_commit}
staging:  ${staging_dir}
log:      ${log_file:-(none)}
jobs:     ${make_jobs}
mode:     $( (( incremental )) && print -n incremental || print -n clean )$( (( dry_run )) && print -n '  (dry run)' )"

    cd "$source_dir"

    run_step git checkout --detach "$target_commit"

    if (( incremental )); then
        [[ -f Makefile ]] \
            || die "--incremental needs an already-configured tree; run without it first"
        print_colored "$COLOR_YELLOW" "==> reusing existing configuration"
    else
        # distclean is only meaningful once a previous run produced a Makefile.
        if [[ -f Makefile ]]; then
            run_step make distclean
        else
            print_colored "$COLOR_YELLOW" "==> no Makefile present; skipping distclean"
        fi

        run_step ./autogen.sh
        run_step ./configure "${configure_flags[@]}" "CFLAGS=${configure_cflags}"
    fi

    run_step make -j"$make_jobs"

    # Start the install from a known state so stale files cannot survive, and
    # so an interrupted run leaves an obviously empty bundle rather than a
    # plausible-looking stale one.
    run_step rm -rf "$staged_app"
    run_step make install

    if (( dry_run )); then
        print_colored "$COLOR_GREEN" "Dry run complete; nothing was built."
        return 0
    fi

    [[ -x "${staged_app}/Contents/MacOS/Emacs" ]] \
        || die "make install finished but ${staged_app} looks incomplete"

    print_colored "$COLOR_GREEN" "Build succeeded."
    "${staged_app}/Contents/MacOS/Emacs" --version | head -2
}

# Printed only on success, so the copy commands are never mistaken for a
# finished build.
print_install_hint() {
    print_colored "$COLOR_GREEN" "
Staged at: ${staged_app}
Log:       ${log_file:-(none)}

To install, quit Emacs and then run:

  sudo ditto \"${staged_app}\" ${installed_app}.incoming
  sudo mv ${installed_app} ${installed_app}.previous
  sudo mv ${installed_app}.incoming ${installed_app}
  sudo rm -rf ${installed_app}.previous

Dragging the bundle in Finder works too and raises the standard auth prompt."
}

# --------------------------------------------------------- argument parse ---

while (( $# )); do
    case "$1" in
        -r|--ref)         target_ref="${2:?--ref needs a value}"; shift 2 ;;
        -j|--jobs)        make_jobs="${2:?--jobs needs a value}"; shift 2 ;;
        -i|--incremental) incremental=1; shift ;;
        -n|--dry-run)     dry_run=1; shift ;;
        --debug)          set -x; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "$make_jobs" == <1-> ]] || die "--jobs must be a positive integer, got '${make_jobs}'"

# ------------------------------------------------------------------- main ---

validate_tools
validate_layout
build_commit="$(resolve_ref)"

mkdir -p "$staging_dir"

# A dry run reports what would happen and leaves no log behind.
if (( dry_run )); then
    run_build "$build_commit"
    exit 0
fi

mkdir -p "$logs_dir"
log_file="${logs_dir}/build-release-$(date +%Y%m%d-%H%M%S).log"

# ERR_EXIT would abort before $pipestatus could be read, so suspend it across
# the pipeline and handle the build's own status explicitly.
setopt LOCAL_OPTIONS NO_ERR_EXIT
run_build "$build_commit" 2>&1 | tee "$log_file"
build_status=${pipestatus[1]}

if (( build_status != 0 )); then
    print_colored "$COLOR_RED" "Build failed (exit ${build_status}). Log: ${log_file}"
    exit "$build_status"
fi

print_install_hint
