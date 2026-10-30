#!/usr/bin/env bash
#
# build-emacs-mac.sh - Build jdtsmith/emacs-mac and install it as
# /Applications/Emacs.app.
#
# Until the macOS 27 fixes are merged, this follows FIX_BRANCH (PR #159,
# which is stacked on the live-resize PR #157). Once every FIX_BRANCH
# commit has landed on BASE_BRANCH (compared by patch, so rebased merges
# count) or the PR shows as merged, it builds BASE_BRANCH instead.
#
# The build happens in a dedicated git worktree of SOURCE_REPO, which is
# reset to the remote branch on every run (the fix branches get
# force-pushed), so never keep local work in it.
#
# Before replacing the installed app, the old one is archived to a
# timestamped zip rather than kept as a second Emacs.app: two bundles with
# the same identifier confuse LaunchServices ("Open With" duplicates).

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Honor NO_COLOR and non-terminal output (pipes, files, CI).
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    COLOR_GREEN="" COLOR_RED="" COLOR_YELLOW="" COLOR_BRIGHTYELLOW="" COLOR_RESET=""
fi

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf '%b%s%b\n' "$color" "$message" "$COLOR_RESET"
}

die() {
    print_colored "$COLOR_RED" "Error: $1"
    exit 1
}

# Sources and branches
SOURCE_REPO="$HOME/dev/oss/emacs"
REPO_SLUG="jdtsmith/emacs-mac"
BASE_BRANCH="emacs-mac-31"
FIX_BRANCH="fix/menus-27"
FIX_PR=159

# Build locations
BUILD_ROOT="$HOME/dev/oss/emacs-builds"
WORKTREE="$BUILD_ROOT/src-release"
STAGING="$BUILD_ROOT/staging-release"
ARCHIVE_DIR="$BUILD_ROOT/previous"
LOG_DIR="$BUILD_ROOT/logs"
APP_DIR="/Applications"
ARCHIVES_TO_KEEP=3

# Build options. --with-mac is the default, but naming it embeds it in the
# binary, which is how link-configuration-files.sh detects the port.
BASE_CFLAGS="-O2 -g"
CONFIGURE_OPTIONS=(--with-mac --enable-mac-self-contained --with-gnutls --without-native-compilation)
BREW_DEPENDENCIES=(autoconf automake pkgconf texinfo gnutls)
# Casks that install their own /Applications/Emacs.app
CONFLICTING_CASKS=(emacs-app emacs emacs-mac emacs-mac-spacemacs-icon)

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

dry_run=false
fetch=true
install=true
build=true
branch_override=""
make_jobs=$(sysctl -n hw.ncpu)

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [options]

Build jdtsmith/emacs-mac from $SOURCE_REPO and install it as
$APP_DIR/Emacs.app. Builds $FIX_BRANCH until it is merged into
$BASE_BRANCH, then $BASE_BRANCH.

Options:
  -n, --dry-run      Show the branch, flags, and steps without building
  -b, --branch NAME  Build this remote branch instead of choosing one
      --no-fetch     Do not fetch from origin first
      --build-only   Build into $STAGING but do not install
      --install-only Install the app staged by an earlier --build-only
  -j, --jobs N       Parallel make jobs (default: $make_jobs)
  -h, --help         Show this help

Rollback: each replaced app is archived as $ARCHIVE_DIR/Emacs-<date>.zip
(newest $ARCHIVES_TO_KEEP kept). Restore one with:
  rm -rf $APP_DIR/Emacs.app && ditto -x -k <zip> $APP_DIR/"
}

# Run a command that changes something, or just show it in a dry run.
run() {
    if [[ "$dry_run" == true ]]; then
        printf '  [dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

check_prerequisites() {
    [[ "$(uname -s)" == Darwin ]] || die "this script only builds on macOS"
    command -v git > /dev/null || die "git not found"
    xcrun --find clang > /dev/null 2>&1 || die "clang not found; run: xcode-select --install"
    command -v brew > /dev/null || die "Homebrew not found"
    git -C "$SOURCE_REPO" rev-parse --git-dir > /dev/null 2>&1 \
        || die "$SOURCE_REPO is not a git clone of $REPO_SLUG"

    local missing=() dependency
    for dependency in "${BREW_DEPENDENCIES[@]}"; do
        brew list --versions "$dependency" > /dev/null 2>&1 || missing+=("$dependency")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_colored "$COLOR_RED" "Missing Homebrew packages: ${missing[*]}"
        print_colored "$COLOR_GREEN" "Install them with: brew install ${missing[*]}"
        [[ "$dry_run" == true ]] || exit 1
    fi
}

# Succeeds when FIX_BRANCH no longer needs to be built on its own.
fix_branch_merged() {
    local fix_branch_exists=false cherry_output pr_info pr_state pr_base
    if git -C "$SOURCE_REPO" rev-parse --verify -q "origin/$FIX_BRANCH" > /dev/null; then
        fix_branch_exists=true
        # git cherry marks commits with no equivalent patch upstream with "+".
        # Capture first: grep -q closing the pipe early would trip pipefail.
        cherry_output=$(git -C "$SOURCE_REPO" cherry "origin/$BASE_BRANCH" "origin/$FIX_BRANCH") \
            || die "could not compare $FIX_BRANCH with $BASE_BRANCH"
        if ! grep -q '^+' <<< "$cherry_output"; then
            return 0
        fi
    fi

    # A squash merge leaves no matching patches, and a merged branch may be
    # deleted, so ask GitHub. Only a merge into BASE_BRANCH counts: the PR
    # is stacked and could first merge into the other fix branch.
    if [[ "$fetch" == true ]] && command -v gh > /dev/null; then
        pr_info=$(gh pr view "$FIX_PR" -R "$REPO_SLUG" --json state,baseRefName \
            -q '.state + " " + .baseRefName' 2> /dev/null || true)
        pr_state=${pr_info%% *}
        pr_base=${pr_info#* }
        if [[ "$pr_state" == MERGED && "$pr_base" == "$BASE_BRANCH" ]]; then
            return 0
        elif [[ "$pr_state" == MERGED ]]; then
            print_colored "$COLOR_YELLOW" "PR #$FIX_PR merged into $pr_base, not yet $BASE_BRANCH"
        elif [[ "$pr_state" == CLOSED ]]; then
            print_colored "$COLOR_RED" "Warning: PR #$FIX_PR was closed without merging"
        fi
    fi

    if [[ "$fix_branch_exists" == false ]]; then
        die "origin/$FIX_BRANCH is gone and PR #$FIX_PR is not known to be merged into $BASE_BRANCH; choose one with --branch"
    fi
    return 1
}

select_branch() {
    if [[ -n "$branch_override" ]]; then
        build_branch=$branch_override
    elif fix_branch_merged; then
        build_branch=$BASE_BRANCH
        print_colored "$COLOR_GREEN" "$FIX_BRANCH is merged into $BASE_BRANCH; building $BASE_BRANCH"
    else
        build_branch=$FIX_BRANCH
    fi
    git -C "$SOURCE_REPO" rev-parse --verify -q "origin/$build_branch" > /dev/null \
        || die "origin/$build_branch not found"
}

# On macOS N with a newer SDK installed, the build can segfault (see the
# emacs-mac README); fall back to the SDK matching this system.
compute_cflags() {
    local os_major sdk_path sdk_version sdk_major sdk_dir fallback_sdk=""
    build_cflags=$BASE_CFLAGS
    os_major=$(sw_vers -productVersion | cut -d. -f1)
    # The SDK clang uses when given no -isysroot. Its directory name may be
    # an unversioned symlink (MacOSX.sdk), so read the version it declares.
    sdk_path=$(xcrun --show-sdk-path 2> /dev/null) || return 0
    sdk_version=$(plutil -extract Version raw "$sdk_path/SDKSettings.plist" 2> /dev/null) || return 0
    sdk_major=${sdk_version%%.*}
    if [[ ! "$sdk_major" =~ ^[0-9]+$ ]] || (( sdk_major <= os_major )); then
        return 0
    fi

    # Xcode may be the active SDK source while only the Command Line Tools
    # carry the older SDK, so look in both.
    for sdk_dir in "$(dirname "$sdk_path")" /Library/Developer/CommandLineTools/SDKs; do
        if [[ -d "$sdk_dir/MacOSX$os_major.sdk" ]]; then
            fallback_sdk="$sdk_dir/MacOSX$os_major.sdk"
            break
        fi
    done
    if [[ -n "$fallback_sdk" ]]; then
        build_cflags="$build_cflags -isysroot $fallback_sdk"
        print_colored "$COLOR_YELLOW" "SDK $sdk_major is newer than macOS $os_major; using $fallback_sdk"
    else
        print_colored "$COLOR_RED" "Warning: SDK $sdk_major is newer than macOS $os_major and MacOSX$os_major.sdk is not installed; the build may fail"
    fi
}

prepare_worktree() {
    local target_ref="origin/$build_branch"
    # Forget a registered worktree whose directory was deleted, or
    # "worktree add" would refuse the path.
    run git -C "$SOURCE_REPO" worktree prune
    if [[ ! -e "$WORKTREE" ]]; then
        previous_commit=""
        run mkdir -p "$BUILD_ROOT"
        run git -C "$SOURCE_REPO" worktree add --detach "$WORKTREE" "$target_ref"
        return
    fi

    # The reset and clean below discard everything, so refuse anything that
    # is not this repo's dedicated worktree (never the main checkout).
    local worktree_real worktree_top worktree_common source_common
    worktree_real=$(realpath "$WORKTREE")
    worktree_top=$(git -C "$WORKTREE" rev-parse --show-toplevel 2> /dev/null) \
        || die "$WORKTREE exists but is not a git worktree"
    [[ "$(realpath "$worktree_top")" == "$worktree_real" ]] \
        || die "$WORKTREE is inside another checkout, not a worktree of its own"
    worktree_common=$(realpath "$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir)")
    source_common=$(realpath "$(git -C "$SOURCE_REPO" rev-parse --path-format=absolute --git-common-dir)")
    [[ "$worktree_common" == "$source_common" ]] \
        || die "$WORKTREE is not a worktree of $SOURCE_REPO"
    [[ "$worktree_real" != "$(realpath "$SOURCE_REPO")" ]] \
        || die "WORKTREE must not be the main checkout"

    previous_commit=$(git -C "$WORKTREE" rev-parse --short HEAD)
    run git -C "$WORKTREE" checkout --force --detach "$target_ref"
    # Build from scratch: a changed branch, CFLAGS, or SDK must not reuse
    # objects or a Makefile from the last build.
    run git -C "$WORKTREE" clean -xfdq
}

show_changes() {
    local new_commit
    new_commit=$(git -C "$SOURCE_REPO" rev-parse --short "origin/$build_branch")
    print_colored "$COLOR_BRIGHTYELLOW" "Building $build_branch at $new_commit"
    if [[ -n "$previous_commit" && "$previous_commit" != "$new_commit" ]]; then
        print_colored "$COLOR_YELLOW" "New since last build ($previous_commit):"
        git -C "$SOURCE_REPO" log --oneline --no-merges "$previous_commit..$new_commit" -- | head -20 || true
    fi
}

build_app() {
    local log_file
    log_file="$LOG_DIR/build-release-$(date +%Y%m%d-%H%M%S).log"
    print_colored "$COLOR_YELLOW" "CFLAGS: $build_cflags"
    print_colored "$COLOR_YELLOW" "configure: --enable-mac-app=$STAGING ${CONFIGURE_OPTIONS[*]}"

    if [[ "$dry_run" == true ]]; then
        run ./autogen.sh
        run ./configure --enable-mac-app="$STAGING" "${CONFIGURE_OPTIONS[@]}" "CFLAGS=$build_cflags"
        run make -j"$make_jobs"
        run make install
        return
    fi

    mkdir -p "$LOG_DIR"
    print_colored "$COLOR_YELLOW" "Log: $log_file"
    # Start from an empty staging bundle so no stale files carry over.
    if [[ -d "$STAGING/Emacs.app" ]]; then
        rm -rf "${STAGING:?}/Emacs.app"
    fi
    # Chained with && because set -e is ignored on the left of "||". Brew's
    # texinfo goes first in PATH since it is keg-only on some systems.
    (
        cd "$WORKTREE" &&
        PATH="$(brew --prefix texinfo)/bin:$PATH" &&
        ./autogen.sh &&
        ./configure --enable-mac-app="$STAGING" "${CONFIGURE_OPTIONS[@]}" "CFLAGS=$build_cflags" &&
        make -j"$make_jobs" &&
        make install
    ) > "$log_file" 2>&1 || die "build failed; see $log_file"
}

# Check the staged app runs and has what this config needs.
verify_app() {
    local emacs_binary="$STAGING/Emacs.app/Contents/MacOS/Emacs"
    if [[ "$dry_run" == true ]]; then
        run "$emacs_binary" --batch -Q --eval "(checks: mac port, GnuTLS)"
        return
    fi
    [[ -x "$emacs_binary" ]] || die "build produced no $emacs_binary"
    "$emacs_binary" --batch -Q --eval '
      (progn
        (unless (featurep (quote mac)) (message "not the mac port") (kill-emacs 1))
        (unless (gnutls-available-p) (message "no GnuTLS") (kill-emacs 1))
        (princ (format "%s\n" (emacs-version))))' \
        || die "staged app failed its checks"
}

# Problems that would stop the install; a dry run reports them and goes on.
install_blocked() {
    if [[ "$dry_run" == true ]]; then
        print_colored "$COLOR_RED" "Install would stop here: $1"
    else
        die "$1"
    fi
}

check_install_target() {
    # Match installed names exactly; brew list --cask NAME also accepts
    # aliases (emacs -> emacs-app), which would report one cask twice.
    local cask installed_casks
    installed_casks=$(brew list --cask -1 2> /dev/null || true)
    for cask in "${CONFLICTING_CASKS[@]}"; do
        if grep -qxF "$cask" <<< "$installed_casks"; then
            install_blocked "Homebrew cask '$cask' owns $APP_DIR/Emacs.app; first run: brew uninstall --cask $cask"
        fi
    done
    if pgrep -f "$APP_DIR/Emacs.app/Contents/MacOS/" > /dev/null; then
        install_blocked "Emacs is running from $APP_DIR/Emacs.app; quit it first"
    fi
    [[ -w "$APP_DIR" ]] || install_blocked "$APP_DIR is not writable"
}

# Keep the newest ARCHIVES_TO_KEEP archives; timestamped names sort by date.
prune_archives() {
    local archives=("$ARCHIVE_DIR"/Emacs-*.zip) archive_count old_archive
    [[ -e "${archives[0]}" ]] || return 0
    archive_count=${#archives[@]}
    (( archive_count > ARCHIVES_TO_KEEP )) || return 0
    for old_archive in "${archives[@]:0:archive_count - ARCHIVES_TO_KEEP}"; do
        run rm -f "$old_archive"
    done
}

# Copy the new app in beside the old one, then swap them with mv (atomic on
# one volume), so no failure leaves /Applications without a working Emacs.
install_app() {
    local target="$APP_DIR/Emacs.app"
    local incoming="$APP_DIR/.Emacs.app.incoming"
    local outgoing="$APP_DIR/.Emacs.app.outgoing"
    local archive
    archive="$ARCHIVE_DIR/Emacs-$(date +%Y%m%d-%H%M%S).zip"

    # Check again: the build is long enough for Emacs to have been opened.
    if pgrep -f "$target/Contents/MacOS/" > /dev/null; then
        install_blocked "Emacs is running from $target; quit it, then rerun"
    fi

    run rm -rf "$incoming" "$outgoing"   # leftovers from an interrupted run
    run ditto "$STAGING/Emacs.app" "$incoming"

    if [[ -d "$target" ]]; then
        print_colored "$COLOR_YELLOW" "Archiving the current app to $archive"
        run mkdir -p "$ARCHIVE_DIR"
        run ditto -c -k --sequesterRsrc --keepParent "$target" "$archive"
        if [[ "$dry_run" == false ]]; then
            unzip -tq "$archive" > /dev/null || die "archive check failed; $target left in place"
        fi
        run mv "$target" "$outgoing"
    fi
    if ! run mv "$incoming" "$target"; then
        if [[ -d "$outgoing" ]]; then
            mv "$outgoing" "$target" || die "could not restore $target; the old app is at $outgoing"
        fi
        die "could not move the new app into place; the previous app was kept"
    fi
    run rm -rf "$outgoing"
    prune_archives

    # Leave LaunchServices with only the installed org.gnu.Emacs; these can
    # fail harmlessly when a copy was never registered.
    run "$LSREGISTER" -f "$target" || true
    run "$LSREGISTER" -u "$STAGING/Emacs.app" || true
    run "$LSREGISTER" -u "$WORKTREE/mac/Emacs.app" || true
    run rm -rf "$STAGING/Emacs.app"
    print_colored "$COLOR_YELLOW" "Rollback: rm -rf $target && ditto -x -k <archive> $APP_DIR/  (archives in $ARCHIVE_DIR)"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run) dry_run=true ;;
        -b|--branch)
            [[ $# -ge 2 ]] || { print_colored "$COLOR_RED" "--branch needs a value"; exit 2; }
            branch_override=$2
            shift
            ;;
        --no-fetch) fetch=false ;;
        --build-only) install=false ;;
        --install-only) build=false ;;
        -j|--jobs)
            [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { print_colored "$COLOR_RED" "--jobs needs a positive number"; exit 2; }
            make_jobs=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

if [[ "$dry_run" == true ]]; then
    print_colored "$COLOR_YELLOW" "Dry run: nothing will be built or installed"
fi

if [[ "$build" == false ]]; then
    # Install the app left by an earlier --build-only run.
    [[ "$install" == true ]] || die "--install-only and --build-only cannot be combined"
    [[ -d "$STAGING/Emacs.app" ]] || install_blocked "no staged app in $STAGING; run with --build-only first"
    build_branch="the staged build"
else
    check_prerequisites
    if [[ "$fetch" == true ]]; then
        # Fetching only updates remote-tracking refs, so it runs in a dry run too.
        print_colored "$COLOR_YELLOW" "Fetching $REPO_SLUG"
        git -C "$SOURCE_REPO" fetch --prune --quiet origin
    fi
    select_branch
    compute_cflags
fi
if [[ "$install" == true ]]; then
    check_install_target
fi
if [[ "$build" == true ]]; then
    prepare_worktree
    show_changes
    build_app
fi
verify_app

if [[ "$install" == true ]]; then
    install_app
fi

if [[ "$dry_run" == true ]]; then
    print_colored "$COLOR_GREEN" "Dry run complete for $build_branch; nothing was changed"
elif [[ "$install" == true ]]; then
    print_colored "$COLOR_GREEN" "Installed $APP_DIR/Emacs.app ($build_branch)"
    print_colored "$COLOR_GREEN" "Link the config if needed: link-configuration-files.sh --emacs mac-port"
else
    print_colored "$COLOR_GREEN" "Built $STAGING/Emacs.app ($build_branch); not installed"
fi
