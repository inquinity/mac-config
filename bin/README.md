# Custom bin directory

This directory contains scripts and wrappers that override or extend system commands.

Scripts in this directory are automatically added to PATH (with priority) via `.zshenv`:
```bash
addpath --move ~/mac-config/bin
```

## git-wt

Wrapper for `git worktree` that automatically manages `.git/info/exclude` entries.

**Usage:**
```bash
git wt add <path> <branch>    # Adds path to .git/info/exclude
git wt remove <path>          # Removes path from .git/info/exclude
git wt list                   # Passes through to git
```

**Why:** Nested worktrees appear as untracked directories in the parent worktree. This script automatically excludes them from `git status` without cluttering the tracked `.gitignore`.

**Why `git wt ...` works (and `git worktree ...` wouldn't):** git resolves
subcommands in this order: config aliases → builtin commands → external
`git-<cmd>` executables on `$PATH`. `worktree` is a compiled-in builtin, so a
same-named script on `$PATH` is never reached. `wt` is not a builtin or an
alias, so git falls through to the PATH lookup, finds `git-wt` here (since
this directory is prepended to `$PATH` in `.zshenv`), and execs it. This only
works because the wrapper uses a distinct name — renaming it back to
`git-worktree` would silently stop it from firing.
