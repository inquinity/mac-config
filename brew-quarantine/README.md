# Brew Quarantine Audit

This repository started with a single-purpose `claude` dequarantine helper. The more general tool is now `fix-brew-quarantine.sh`, which scans Homebrew-managed artifacts and only removes `com.apple.quarantine` from the specific artifact roots that actually need it.

## What It Does

- discovers installed Homebrew formula version roots under `$(brew --cellar)`
- discovers installed Homebrew cask version roots under `$(brew --caskroom)`
- scans those roots for `com.apple.quarantine`
- groups findings by artifact root, such as `codex/0.115.0` or `openjdk/25.0.2`
- shows a report with every affected path before making changes
- prompts for confirmation unless `--yes` is passed

If a cask payload is a symlink into another location such as `/Applications`, the report shows the resolved real target and the fix operates on that real path.

This is intentionally narrower than `sudo xattr -r -d com.apple.quarantine /opt/homebrew`. It fixes only the specific formula or cask versions that currently have quarantine attributes.

## Common Cases Covered

- `claude` if installed as a Homebrew formula or cask
- `codex` cask updates
- `openjdk` or other Java formula updates
- `codeql` cask contents, including embedded Java runtimes

Because the scan works at the Homebrew artifact-root level, it naturally covers Java homes inside formula/cask directories without needing a separate special case.

## Usage

```sh
chmod +x ./fix-brew-quarantine.sh
./fix-brew-quarantine.sh
```

Dry-run only:

```sh
./fix-brew-quarantine.sh --dry-run
```

Fix without prompting:

```sh
sudo ./fix-brew-quarantine.sh --yes
```

Limit the scan to likely problem packages:

```sh
./fix-brew-quarantine.sh --match 'claude|codex|codeql|openjdk|java'
```

Add an extra root outside standard Homebrew locations:

```sh
./fix-brew-quarantine.sh --path /custom/path/to/artifact
```

## Notes

- The script looks only for `com.apple.quarantine`. It does not touch `com.apple.provenance`.
- Some artifacts may require `sudo` to remove attributes, depending on ownership and permissions.
- This is designed as a manual or scheduled audit tool. It is a better fit than a permanent background watcher when the goal is "find and fix current Homebrew quarantine issues safely."
