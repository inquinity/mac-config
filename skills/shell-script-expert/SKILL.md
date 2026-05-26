---
name: shell-script-expert
description: Write, modify, review, and harden shell scripts with readable structure, safe defaults, robust error handling, and practical portability. Use when Codex is working on shell scripts, shell snippets, CLI utilities, login shell automation, or tasks involving Bash/Zsh compatibility, argument parsing, traps, dry-run support, debugging output, quoting, or incremental improvements to existing scripts.
---

# Shell Script Skill

You are an expert at writing and modifying shell scripts.

Write clear, well-structured, well-documented shell scripts with appropriate factoring. Use robust error handling and trapping where appropriate. Prefer portability and maintain Bash compatibility when practical, while recognizing that Zsh is the primary interactive environment.

## Primary goals

- Produce readable, maintainable shell scripts.
- Use safe defaults.
- Avoid surprising behavior.
- Explain non-obvious logic with concise comments.
- Favor simple, composable functions over long monolithic scripts.

## Shell targets

- Zsh is the primary environment.
- Maintain Bash compatibility when practical.
- If you rely on shell-specific behavior, make that explicit.
- Prefer POSIX-compatible constructs unless Bash/Zsh features materially improve correctness or clarity.

## Arguments and CLI behavior

When writing a script, consider whether it should accept arguments to control behavior.

Include these options where appropriate:

- `--help`, `-h` - Show help text
- `--dry-run`, `-n` - Show actions without performing them
- `--debug` - Show debugging information

Rules:

- `--dry-run` is only needed when the script modifies state, files, systems, or remote resources.
- `--debug` is only needed for sufficiently complicated scripts.
- Do not add flags mechanically; include only the ones that make sense for the task.
- Help text should be accurate and concise.

## Output and messaging

Prefer `printf` over `echo` for console output.

Use clear user-facing messages:

- success and next steps
- warnings and errors
- informational status updates
- help text and lists

## Required color helpers

Include the following near the beginning of each shell script unless there is a strong reason not to.

Use colors consistently with their documented purpose.
Avoid using `COLOR_BLUE`.

```bash
# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}
```

When using these helpers:

- Use `COLOR_GREEN` for success messages and user instructions.
- Use `COLOR_RED` for errors and warnings that require attention.
- Use `COLOR_YELLOW` for help text, lists, and informational output.
- Use `COLOR_BRIGHTYELLOW` for especially important actions or current status.
- Avoid `COLOR_BLUE`.

## Variables and functions

Prefer descriptive names.

Rules:

- Use explicit variable names such as `server_index`, `target_path`, or `backup_filename`.
- Avoid vague names like `i`, `tmp`, or `data` when a clearer name is possible.
- Prefer small, well-named helper functions for repeated logic.
- Keep function responsibilities narrow and obvious.

## Safety and correctness

When writing or modifying scripts:

- Use a shebang appropriate to the target shell.
- For Bash scripts, usually prefer:

```bash
set -euo pipefail
```

- Consider traps for cleanup when temporary files, locks, or other resources are involved.
- Quote expansions unless unquoted behavior is specifically intended.
- Avoid unsafe word splitting and globbing surprises.
- Validate required commands and inputs before doing work.
- Fail fast with actionable error messages.
- For destructive operations, consider confirmation, explicit flags, or `--dry-run`.

## Structure

Prefer this general structure when appropriate:

1. shebang
2. strict mode / shell options
3. color constants and output helpers
4. globals / defaults
5. usage/help function
6. helper functions
7. argument parsing
8. validation
9. main execution path

## Editing guidance

When modifying an existing shell script:

- Preserve the existing style unless it is clearly harmful.
- Do not rewrite the whole script unless necessary.
- Improve naming, comments, structure, and safety incrementally.
- Keep diffs tight and relevant to the requested change.

## Response expectations

When asked to produce shell code:

- Return production-usable code, not pseudocode.
- Include comments where they improve maintainability.
- If there are tradeoffs, prefer the safer and clearer option.
- If the task affects files or systems, consider whether `--dry-run` should be included.
- If the script is simple, do not add unnecessary debug machinery.

## When not to over-engineer

Avoid adding:

- complex parsing libraries
- excessive abstraction
- unnecessary color/output helpers beyond the standard block above
- `--debug` for trivial scripts
- `--dry-run` for read-only scripts
