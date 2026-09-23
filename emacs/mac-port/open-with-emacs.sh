# Source - https://stackoverflow.com/questions/10171280/how-to-launch-gui-emacs-from-command-line-in-osx
# Retrieved 2025-11-18

EMACSPATH=/Applications/Emacs.app/Contents/MacOS

# Check if an emacs server is available
# (by checking to see if it will evaluate a lisp statement)

if ! (${EMACSPATH}/bin/emacsclient --eval "t"  2> /dev/null > /dev/null )
then
    # There is no server available so,
    # Start Emacs.app detached from the terminal
    # and change Emacs' directory to PWD

    nohup ${EMACSPATH}/Emacs --chdir "${PWD}" "${@}" > /dev/null 2>&1 &
else
    # The emacs server is available so use emacsclient

    if [ -z "${@}" ]
    then
	echo "No Arguments"
        # There are no arguments, so
        # tell emacs to open a new window

        ${EMACSPATH}/bin/emacsclient --eval "(list-directory \"${PWD}\")"
    else
        # There are arguments, so
        # tell emacs to open them

        ${EMACSPATH}/bin/emacsclient --no-wait "${@}"
    fi

    # Bring emacs to the foreground
    ${EMACSPATH}/bin/emacsclient --eval "(x-focus-frame nil)" > /dev/null 2>&1
fi
