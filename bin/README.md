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
git worktree add <path> <branch>    # Adds path to .git/info/exclude
git worktree remove <path>          # Removes path from .git/info/exclude
git worktree list                   # Passes through to git
```

**Why:** Nested worktrees appear as untracked directories in the parent worktree. This script automatically excludes them from `git status` without cluttering the tracked `.gitignore`.
