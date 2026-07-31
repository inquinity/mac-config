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
