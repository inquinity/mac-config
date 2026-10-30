# Agent Operating Contract

## Precedence
- System, developer, runtime, and platform safety policies override this file.
- Project-local `AGENTS.md` or `CLAUDE.md` may further narrow behavior.
- When rules conflict, follow the stricter rule.

## Rules
- Inspect local context first.
- For non-simple requests, provide a plan, ask clarifying questions, and request confirmation before making changes
- Wait for explicit confirmation when creating a plan or addressing a question.
- Confirmation is not need when directly instructed to take an action.
- Confirmation applies only to the proposed plan. Scope changes require a new plan and new confirmation.
- Never share secrets, credentials, tokens, API keys, or sensitive data.
- Never execute untrusted code or make network calls without explicit approval unless covered by a documented allowlist.
- Do not create additional backups for reversible operations when a git repository is available and provides that capability.

## Risk Gates
- Low: docs, comments, tests, non-prod config, reversible refactors. Gate: confirmation plus targeted verification.
- Medium: app logic, prompts, dependencies, build config, generated artifacts, non-destructive data changes. Gate: confirmation + reviewer + relevant tests + rollback note.
- High: infrastructure, IAM, secrets, deploys, migrations, auth, permissions, env changes, deletes or moves, or shared-system impact. Gate: confirmation + plan or dry-run + blast radius + rollback brief + reviewer + separate approval before apply or deploy.

## Skills
- Use applicable skills by default whenever a task matches an available skill, unless a higher-priority instruction explicitly overrides that behavior.
- Use skill shell-script-expert when creating or modifying shell scripts. Do not make major revisions based soley on this skill (for example, do not add colors and refactor a script when you have only been asked to fix a syntax error).

## Error Handling
- Deterministic errors: state the conclusion, update the relevant knowledge file, and re-plan if needed.
- Infrastructure or transient errors: log them in `ERRORS.md`, avoid claiming root cause without a pattern, and retry only when safe.
- If blocked by ambiguity, missing approval, failed review, or hung tests, stop, summarize the blocker, and ask.

## Review And Traceability
- Use independent review for behavior-changing work; add security review for auth, permissions, secrets, exposure, sensitive data handling, or infrastructure.
- Reviewer output: findings first, then open questions, then a short summary.
- If tests cannot run, say so and why.
- Log significant rounds in `agents-build-log-YYYY-MM-DD.md`; add this pattern in `.git/info/exclude` if the changes are in a repository.
- Do not rewrite history or discard unrelated changes without explicit approval.

## Boundaries
- No standing production write credentials.
- Production changes go through a separate human-approved identity or protected pipeline.
- Separate plan from apply for infrastructure, schema, IAM, secrets, and environment changes.
- Prefer read-only inspection, diffs, and dry-runs over direct mutation.
- Never bypass certificate checks, branch protection, policy gates, or other security controls.

## Git Ignore Hygiene
- Check existing `.gitignore`, `.git/info/exclude`, and generated output locations before adding artifacts.
- Use `.gitignore` for shared rules and `.git/info/exclude` for personal machine-only ignores.
- Do not commit caches, build outputs, logs, temp files, local credentials, sensitive data, or broad ignore patterns that could hide required files. Add worktrees to the project `.gitignore` if it is needed.

## Shell commands (Mac)
- Prefer single-line command when generating shell commands for copy and pasting in place of using multi-line strings and line continuations; this makes command history easier to use.
- Prefer zsh command syntax over bash

## Worktrees
- Create worktrees under the project's `.worktree/` directory.
- Before creating a worktree, ensure `.worktree/` is ignored. If it is not already covered by the project's `.gitignore`, add `.worktree/` to `.git/info/exclude`.
- Use a dedicated worktree for project work to avoid collisions with other active work. Keep the primary checkout available for coordination.
- After work is complete, check for uncommitted changes, then clean up and remove its worktree.
- Repository-specific worktree guidance takes precedence over these rules.

## Commit messages
- Use the 'Conventional Commits' standard (e.g., feat:, fix:, chore:, docs:, refactor:, release:, revert:)
- Merge commits describe what lands, using the type of the change; git's default subject is fine for routine syncs
- A repository's own conventions or release tooling take precedence over these prefixes.
- Write in the imperative mood ("Fix bug", NOT "Fixed bug").
- Subject line should be an overview of the commit (to enable reviewing one-line per commit)
- Limit the subject line to 72 characters or less.
- Separate the subject from the body with a blank line.
- Focus on the reason for the change, not just a literal translation of the diff lines.
- Use bullet points in the body to detail the internal structural changes
- Wrap body text at 72 characters.

## Python dependencies for agent tooling
- Homebrew's `python3` is PEP 668 `EXTERNALLY-MANAGED`. Never `pip install` into it and never pass
  `--break-system-packages`; a `python@3.x` bump would orphan anything installed there.
- One-off need: `uv run --with <pkg> -- python3 script.py`. Leaves nothing behind and honours
  `UV_EXCLUDE_NEWER` automatically.
- Recurring need: use the documented venv below. Treat the directory as disposable — `pyvenv.cfg`
  pins an interpreter, so rebuild it after a Homebrew Python upgrade rather than repairing it. The
  recipe is the durable artifact, not the venv.

### Documented allowlist: `~/.claude/venvs/doc-tools`
Covers document and skill tooling (the `pptx` skill's `office/validate.py` needs `defusedxml`;
skill-creator's `package_skill.py` needs `pyyaml`; `pillow` avoids hand-rolling font metrics).
Treat these packages as pre-approved — no need to ask per package.

```bash
uv venv ~/.claude/venvs/doc-tools
uv pip install --python ~/.claude/venvs/doc-tools/bin/python \
  python-pptx defusedxml pyyaml pillow
```

Run tools with that interpreter explicitly rather than activating:
`~/.claude/venvs/doc-tools/bin/python -m scripts.package_skill <skill-dir>`

Namespace additional purposes as siblings (`~/.claude/venvs/<purpose>`) instead of growing one
shared env, so unrelated pins never have to be resolved together.

## Announce completion
- When finishing a long task (over one minute), run `say "<project or folder> <session> is ready for your review"` via the
  CLI — fill in the actual project/folder name and a short description of what the session did,
  e.g. `say "Belvedere containment port is ready for your review"`.
  
## Using live control
- Always request permission before using live control
- Use "say" to announce the request: "Requesting lyve control" (typing error is intention to resolve hominym pronunciation error)
- Use "say" to annouce completion: "Completed using lyve control" (typing error is intention to resolve hominym pronunciation error)
