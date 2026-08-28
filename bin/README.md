# Custom bin directory

This directory contains scripts and wrappers that override or extend system commands.

Scripts in this directory are automatically added to PATH (with priority) via `.zshenv`:
```bash
addpath --move ~/mac-config/bin
```

## git-worktree

Wrapper for `git worktree` that automatically manages `.git/info/exclude` entries.

**Usage:**
```bash
git-worktree add <path> <branch>    # Adds path to .git/info/exclude
git-worktree remove <path>          # Removes path from .git/info/exclude
git-worktree list                   # Passes through to git
```

**Why:** Nested worktrees appear as untracked directories in the parent worktree. This script automatically excludes them from `git status` without cluttering the tracked `.gitignore`.

**⚠️ Not currently wired up to `git worktree`.** Git resolves subcommands in this
order: config aliases → builtin commands → external `git-<cmd>` executables on
`$PATH`. `worktree` is a builtin (compiled into git since 2.5), so git never
falls through to a PATH lookup for it — PATH priority has no effect on builtin
subcommands, and neither does a `git config alias.worktree` override. Typing
`git worktree add ...` invokes real git directly; this script is skipped
entirely, regardless of where its directory sits in `$PATH`.

Until a shell-level `git` function/alias is added (one that inspects `$1` and
routes `worktree` calls here before falling back to real git), invoke this
script directly as `git-worktree ...`, not via `git worktree ...`.
