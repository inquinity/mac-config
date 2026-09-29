# Agent Operating Contract

## ChatGPT and Codex Plugin Packaging
- Package reusable skills for ChatGPT and Codex as a portable plugin. Put the required `plugin.json` manifest at the plugin root and put each skill in `skills/<skill-name>/SKILL.md`.
- Keep optional portable components at that same root: `mcp.json` for bundled MCP servers, `assets/` for packaged visual assets, and `hooks/` only when a lifecycle hook is required. Keep every manifest path relative to the plugin
  root, prefixed with `./`, and inside that root.
- Put OpenAI-specific presentation, registered MCP app mappings, and hook settings in `extensions.com.openai` in the root `plugin.json`. Add `.codex-plugin/plugin.json` only when a legacy compatibility manifest is specifically needed; do not maintain both sources of OpenAI settings.
- Prefer the `plugin-creator` skill to scaffold a new plugin or marketplace entry. Validate manifest references, skill frontmatter, and the final archive layout before handing off a package. The archive must contain the plugin root (or one top-level directory containing it), not loose skill files.
- Never include `.venv/`, caches, logs, credentials, local configuration, or other development-only files in a plugin package.

### Python tooling for plugin work
- Before running Python-based plugin or skill tooling, use this repository's `.venv`. Do not rely on the Homebrew/global `python3` or on a previously activated shell.
- If `.venv/bin/python` does not exist, create the venv with `python3 -m venv .venv`. When dependency installation and its required network access are authorized, activate it and install the validator dependency:

  ```zsh
  source .venv/bin/activate
  python -m pip install PyYAML
  ```

- In the same shell command that invokes Python tooling, explicitly source the venv and use `python`, for example:

  ```zsh
  source .venv/bin/activate
  python /Users/robert.altman@optum.com/.codex/skills/.system/skill-creator/scripts/quick_validate.py <skill-folder>
  ```

- Keep `.venv/` as a local-only artifact. Add it to `.git/info/exclude` if it is not already ignored; do not add a broad shared ignore rule solely for the venv.

