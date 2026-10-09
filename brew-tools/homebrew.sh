# homebrew.sh
#
# Wraps the `brew` command so that `install`, `upgrade`, and `reinstall` run
# through brew-tools/brew-safe.sh's cool-off pin (homebrew/core is checked
# out at the commit from N days ago for the duration of the command, then
# restored) instead of hitting bottles that are too new for a curated
# mirror to have promoted yet. Every other subcommand -- list, info,
# doctor, search, tap, update, etc. -- passes straight through to the real
# brew, untouched.
#
# This file has no opinion on when it should be loaded -- see zshrc, which
# only sources it on machines that actually sit behind such a mirror. Kept
# that way so this and brew-safe.sh can be handed to anyone running plain
# Homebrew, with no assumptions about a particular company's network baked
# in.
#
# Named homebrew.sh rather than brew.sh so a `which`/`type` lookup on the
# `brew` command isn't one grep away from this file of the same name.
#
# The cool-off length itself is not set here: brew-safe.sh reads it from
# $OPTUM_HOMEBREW_MIN_RELEASE_AGE and refuses to run without it, rather than
# this wrapper silently picking a number.
brew() {
    case "$1" in
        install|upgrade|reinstall)
            ~/mac-config/brew-tools/brew-safe.sh -- "$@"
            ;;
        *)
            command brew "$@"
            ;;
    esac
}
