#!/usr/bin/env bash
# Open files (or the current directory) in GUI Emacs, reusing a running
# server via emacsclient when available.
#
# Source - https://stackoverflow.com/questions/10171280/how-to-launch-gui-emacs-from-command-line-in-osx
# Retrieved 2025-11-18

EMACSPATH=/Applications/Emacs.app/Contents/MacOS

# Check if an emacs server is available
# (by checking to see if it will evaluate a lisp statement)

if ! "${EMACSPATH}/bin/emacsclient" --eval "t" > /dev/null 2>&1
then
    # There is no server available so,
    # Start Emacs.app detached from the terminal
    # and change Emacs' directory to PWD

    nohup "${EMACSPATH}/Emacs" --chdir "${PWD}" "$@" > /dev/null 2>&1 &
else
    # The emacs server is available so use emacsclient

    if [ "$#" -eq 0 ]
    then
        # There are no arguments, so
        # tell emacs to show the current directory

        "${EMACSPATH}/bin/emacsclient" --eval "(dired \"${PWD}\")" > /dev/null
    else
        # There are arguments, so
        # tell emacs to open them

        "${EMACSPATH}/bin/emacsclient" --no-wait "$@"
    fi

    # Bring emacs to the foreground
    "${EMACSPATH}/bin/emacsclient" --eval "(x-focus-frame nil)" > /dev/null 2>&1
fi
