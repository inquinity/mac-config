# Brew Quarantine Audit

`fix-brew-quarantine.sh` scans Homebrew-managed formula and cask artifacts for
`com.apple.quarantine`, groups the results by artifact, and removes quarantine
only from paths that are likely to trigger Gatekeeper problems.

This started as a safer replacement for:

```sh
sudo find /opt/homebrew -xdev -xattrname com.apple.quarantine -print 2>/dev/null
sudo xattr -r -d com.apple.quarantine /opt/homebrew 2>/dev/null
```

The broad command still works as a blunt instrument, but it is too large for
company-wide use: it scans all of `/opt/homebrew`, removes every quarantine
record it can find, and does not explain which formula or cask caused the
problem. This script keeps the default workflow narrow and reviewable.

## What It Does

- discovers installed Homebrew formula version roots under `$(brew --cellar)`
- discovers installed Homebrew cask version roots under `$(brew --caskroom)`
- scans those artifact roots for `com.apple.quarantine`
- groups findings by formula or cask name and version
- classifies each quarantined path as actionable or informational
- prompts before removing quarantine unless `--yes` is passed

Actionable paths include files that do not have Gatekeeper's user-approved
quarantine bit, plus quarantined executables, app bundles, or packages whose
code signature verifies as invalid. Informational records are user-approved
quarantine records and are not removed by default or by `--yes`.

If a cask payload is a symlink into another location such as `/Applications`,
the report shows the resolved real target and the fix operates on that real
path.

## Usage

Make sure the script is executable:

```sh
chmod +x ./fix-brew-quarantine.sh
```

List affected formulas and casks, then prompt to fix:

```sh
./fix-brew-quarantine.sh
```

List and fix without prompting:

```sh
./fix-brew-quarantine.sh --yes
```

Show detailed path-level output:

```sh
./fix-brew-quarantine.sh --verbose
```

Show detailed output and fix without prompting:

```sh
./fix-brew-quarantine.sh --verbose --yes
```

Dry-run only:

```sh
./fix-brew-quarantine.sh --dry-run
```

Limit the scan to likely problem packages:

```sh
./fix-brew-quarantine.sh --match 'claude|codex|codeql|openjdk|java'
```

Add an extra root outside standard Homebrew locations:

```sh
./fix-brew-quarantine.sh --path /custom/path/to/artifact
```

Show user-approved informational records:

```sh
./fix-brew-quarantine.sh --include-approved --verbose
```

## Why It Usually Runs Without Sudo

On current macOS releases, removing `com.apple.quarantine` is tied to the file
owner, not just root privileges. Most Homebrew artifacts under `/opt/homebrew`
are owned by the installing user, so running the script as that user is often
both sufficient and more reliable than `sudo`.

If the script is run with `sudo`, it attempts quarantine removal as
`$SUDO_USER` for files owned by that user. The simpler recommended path is to
run without `sudo` first.

## Notes

- The script looks only for `com.apple.quarantine`.
- It does not modify `com.apple.provenance`.
- It does not launch quarantined executables or run Gatekeeper assessment
  commands that can hang or display dialogs.
- It uses `codesign --verify` only as a static check for quarantined executable
  candidates.
