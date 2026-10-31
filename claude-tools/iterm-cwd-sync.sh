#!/usr/bin/env bash
#
# iterm-cwd-sync.sh - Claude Code hook that tells iTerm2 Claude's working
# directory, so iTerm2's Claude Code integration (the Diff window,
# option-shift-command-2, and the git status toolbar) follows worktrees.
#
# Why this is needed: the Diff window runs git in the Chat session's
# session.path. Without shell integration iTerm2 learns that path by polling
# the foreground process, but it does not re-poll while a full-screen program
# like claude is running. When Claude moves into a worktree, the claude
# process changes directory but iTerm2 keeps the old path, so the Diff window
# shows the main checkout instead of the worktree.
#
# This hook pushes the directory with iTerm2's OSC 1337 CurrentDir sequence.
# Claude Code's own hook "terminalSequence" output only allows OSC 0/1/2/9/
# 99/777, so the sequence is written to the claude process's terminal device.
#
# Register it in ~/.claude/settings.json for these events:
#   SessionStart  -> report the session directory (covers claude --worktree)
#   CwdChanged    -> report the new directory (EnterWorktree / ExitWorktree)
#   SessionEnd    -> report the launching shell's directory again, so iTerm2
#                    is not left pointing at a worktree that may be removed
#
# The hook reads the hook JSON on stdin and writes nothing to stdout. It
# always exits 0: a failure here must never block or disturb Claude.

set -uo pipefail

usage() {
    cat <<'USAGE'
iterm-cwd-sync.sh - Claude Code hook that reports Claude's working directory
to iTerm2 so its Claude Code Diff window follows worktrees.

Usage (from a Claude Code hook; hook JSON on stdin):
  iterm-cwd-sync.sh

Handles the SessionStart, CwdChanged and SessionEnd events; others are ignored.
USAGE
}

# Walk up from this hook to the claude process that ran it and print
# "<pid> <tty>". Stop at the first claude ancestor: a headless session
# (claude -p run from another session's Bash tool, background agents) has no
# terminal, and climbing past it would reach -- and repoint -- the outer
# session's terminal. Prints nothing when that claude has no terminal.
find_claude_terminal() {
    local ancestor_pid=$PPID
    local ancestor_command ancestor_tty
    while [[ "$ancestor_pid" -gt 1 ]]; do
        ancestor_command=$(ps -o comm= -p "$ancestor_pid" 2>/dev/null)
        if [[ "${ancestor_command##*/}" == claude ]]; then
            ancestor_tty=$(ps -o tty= -p "$ancestor_pid" 2>/dev/null | tr -d ' ')
            if [[ -n "$ancestor_tty" && "$ancestor_tty" != "??" ]]; then
                printf '%s %s\n' "$ancestor_pid" "$ancestor_tty"
            fi
            return 0
        fi
        ancestor_pid=$(ps -o ppid= -p "$ancestor_pid" 2>/dev/null | tr -d ' ')
        [[ -n "$ancestor_pid" ]] || return 0
    done
}

# Current working directory of a process, or nothing if it cannot be read.
# -b and -w keep lsof from stalling on hung network mounts or warning about them.
process_cwd() {
    lsof -b -w -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
}

# True if the text holds C0 controls or DEL, or UTF-8 encoded C1 controls
# (bytes C2 80 through C2 9F). Matched bytewise in the C locale so ordinary
# non-ASCII characters in a path are still accepted.
has_control_characters() {
    local LC_ALL=C
    [[ "$1" == *[[:cntrl:]]* || "$1" == *$'\xc2'[$'\x80'-$'\x9f']* ]]
}

# Write to the terminal without risking a hang: a flow-stopped terminal
# (Ctrl-S) blocks writes, and Claude would wait on this hook. Give up after
# about a second.
write_to_terminal_bounded() {
    local terminal_path=$1
    local sequence=$2
    local _
    printf '%s' "$sequence" >"$terminal_path" &
    local writer_pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$writer_pid" 2>/dev/null || return 0
        sleep 0.1
    done
    kill "$writer_pid" 2>/dev/null
}

# Directory to report for this event, or nothing to leave iTerm2 alone.
directory_for_event() {
    local hook_input=$1
    local claude_pid=$2
    local event_name parent_pid parent_command
    event_name=$(jq -r '.hook_event_name // empty' <<<"$hook_input")
    case $event_name in
        SessionStart) jq -r '.cwd // empty' <<<"$hook_input" ;;
        CwdChanged) jq -r '.new_cwd // empty' <<<"$hook_input" ;;
        SessionEnd)
            # The shell that launched claude is where the session returns to.
            # Skip when the parent is not a shell (exec claude, a profile
            # command): its directory is not one the user chose.
            parent_pid=$(ps -o ppid= -p "$claude_pid" 2>/dev/null | tr -d ' ')
            [[ -n "$parent_pid" ]] || return 0
            parent_command=$(ps -o comm= -p "$parent_pid" 2>/dev/null)
            parent_command=${parent_command##*/}
            [[ "${parent_command#-}" == *sh ]] && process_cwd "$parent_pid"
            ;;
    esac
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        return 0
    fi

    local hook_input
    hook_input=$(cat)

    # Only iTerm2 understands the sequence; elsewhere do nothing.
    [[ "${TERM_PROGRAM:-}" == "iTerm.app" || -n "${ITERM_SESSION_ID:-}" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local claude_pid claude_tty
    read -r claude_pid claude_tty < <(find_claude_terminal) || true
    [[ -n "${claude_pid:-}" && -w "/dev/${claude_tty:-}" ]] || return 0

    local target_directory
    target_directory=$(directory_for_event "$hook_input" "$claude_pid")
    # Require an existing absolute path; reject control characters, which
    # could end the escape sequence early.
    [[ "$target_directory" == /* && -d "$target_directory" ]] || return 0
    has_control_characters "$target_directory" && return 0

    write_to_terminal_bounded "/dev/$claude_tty" \
        "$(printf '\033]1337;CurrentDir=%s\007' "$target_directory")"
}

main "$@" 2>/dev/null
exit 0
