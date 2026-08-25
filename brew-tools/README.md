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

---

# brew-safe.sh

Runs a `brew` command against a `homebrew/core` tap pinned to a commit from N
days ago (default 6), so a freshly published formula cannot be installed until
it has been public for that long.

This is the Homebrew counterpart to the Python cool-off settings already in
`.zshenv-uhg`:

| Tool | Setting |
| --- | --- |
| pip | `PIP_UPLOADED_PRIOR_TO="P5D"` |
| poetry | `POETRY_SOLVER_MIN_RELEASE_AGE=5` |
| uv | `UV_EXCLUDE_NEWER="5 days"` |
| brew | `brew-safe.sh` (this script) |

**Status: kept in reserve, not in use.** Nothing invokes it and it is not on
`PATH`. It started as a `brew-safe()` function in `~/.zshrc` that was never
actually run — atuin history shows 0 invocations against 67 plain `brew`
commands. It would not have worked either: it restored the tap with
`git checkout master`, but `homebrew/core`'s branch is `main`, so every run
would have left the tap detached at a stale commit with the error hidden by
`2>/dev/null`. Subsequent `brew` commands would then have silently resolved
against old formulae.

## Usage

```sh
./brew-safe.sh install jq              # install jq as it existed 6 days ago
./brew-safe.sh --days 14 upgrade jq    # use a 14-day cool-off
./brew-safe.sh --dry-run install jq    # show what would happen
./brew-safe.sh --help
```

The first non-option argument and everything after it is passed through to
`brew`. Use `--` when a brew argument would otherwise look like one of this
script's own options.

| Option | Effect |
| --- | --- |
| `--days N` | Cool-off period in days (default 6) |
| `--dry-run`, `-n` | Print the checkout/brew/restore steps without running them |
| `--debug` | Show the resolved tap path and original ref |
| `--help`, `-h` | Show usage |

## How It Restores State

The tap is a real git checkout, so pinning means detaching it. That is the risky
part, and it is handled as follows:

- The original ref is captured before anything changes — the branch name when
  `HEAD` is on one, otherwise the raw commit. It is never assumed to be `main`,
  so a tap someone else left detached is restored to where it was found.
- Restoration runs from an `EXIT` trap, so it happens on success, on `brew`
  failure, and on `Ctrl-C`. `INT` and `TERM` are trapped to exit (130 / 143) so
  the `EXIT` trap fires exactly once.
- If restoration itself fails, the script says so in red and prints the exact
  `git checkout` command to run. It never fails silently.
- The script refuses to start if the tap has uncommitted changes, since a
  checkout could discard them.
- `HOMEBREW_NO_INSTALL_FROM_API=1` makes brew read the pinned local tap instead
  of the formula API, and `HOMEBREW_NO_AUTO_UPDATE=1` stops brew from fetching
  the tap and undoing the pin. Both are set by the script rather than inherited,
  so it behaves the same outside an interactive shell.

The script exits with `brew`'s own exit status.

## Requirements

`homebrew/core` must be tapped as a git repository (`brew tap --force
homebrew/core`) and not a shallow clone — pinning by date needs history. The
script checks both and explains the fix if either is missing.
