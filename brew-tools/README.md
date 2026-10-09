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
days ago, so a freshly published formula cannot be installed until it has been
public for that long. N comes from `--days` or `$OPTUM_HOMEBREW_MIN_RELEASE_AGE`
— there is no built-in default, and the script refuses to run if neither is set,
rather than silently picking a number.

This is the same idea as a few cool-off settings other package managers already
support:

| Tool | Setting |
| --- | --- |
| pip | `PIP_UPLOADED_PRIOR_TO="P5D"` |
| poetry | `POETRY_SOLVER_MIN_RELEASE_AGE=5` |
| uv | `UV_EXCLUDE_NEWER="5 days"` |
| brew | `brew-safe.sh` + `$OPTUM_HOMEBREW_MIN_RELEASE_AGE` (this script) |

## Usage

```sh
export OPTUM_HOMEBREW_MIN_RELEASE_AGE=6
./brew-safe.sh install jq              # install jq as it existed 6 days ago
./brew-safe.sh --days 14 upgrade jq    # one-off override: use a 14-day cool-off
./brew-safe.sh --dry-run install jq    # show what would happen
./brew-safe.sh --help
```

The first non-option argument and everything after it is passed through to
`brew`. Use `--` when a brew argument would otherwise look like one of this
script's own options.

| Option / Variable | Effect |
| --- | --- |
| `--days N` | Cool-off period in days. Overrides `$OPTUM_HOMEBREW_MIN_RELEASE_AGE` when given |
| `$OPTUM_HOMEBREW_MIN_RELEASE_AGE` | Cool-off period in days, used when `--days` is not given. One of the two is required |
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

---

# homebrew.sh

A shell function that replaces `brew` so that `install`, `upgrade`, and
`reinstall` run through `brew-safe.sh`'s cool-off pin instead of hitting it
directly. Every other subcommand — `list`, `info`, `doctor`, `search`, `tap`,
`update`, etc. — passes straight through to the real `brew`, untouched.

```sh
brew() {
    case "$1" in
        install|upgrade|reinstall)
            /path/to/brew-tools/brew-safe.sh -- "$@"
            ;;
        *)
            command brew "$@"
            ;;
    esac
}
```

`command brew "$@"` in the passthrough branch is load-bearing: since `brew` is
now a shell function, a plain `brew "$@"` there would call itself recursively
forever. `command` explicitly skips any function or alias named `brew` and
runs the real executable.

## Usage

Source it from a shell startup file to make the `brew` function available:

```sh
source /path/to/brew-tools/homebrew.sh
```

This file does not set `$OPTUM_HOMEBREW_MIN_RELEASE_AGE` and has no opinion on
when it should be loaded — both are left to whatever sources it, so it (and
`brew-safe.sh`) can be dropped into any shell setup with no assumptions about
when the cool-off should apply.

---

# reset-brew.sh

Fully removes a Homebrew installation on macOS, on both layouts:

- **Apple Silicon** — everything lives under `/opt/homebrew`, so removing that
  one directory is a complete, clean removal.
- **Intel** — Homebrew installs into `/usr/local`, a directory shared with the
  rest of the system. The script only removes paths Homebrew itself owns there
  (`Cellar`, `Caskroom`, `opt`, `var/homebrew`, `Frameworks`, the brew repo,
  a short list of known completion/doc files) plus symlinks in `bin`, `sbin`,
  `lib`, `include`, and `share` that have gone dangling because the Cellar
  entry they pointed to is already removed. It never deletes a symlink that
  still resolves, and never touches a non-symlink file in those shared
  directories.

Both prefixes are checked regardless of the detected architecture, in case of
a mismatched or migrated install. Caches under `~/Library/Caches/Homebrew`,
`~/.cache/Homebrew`, and `~/.brew` are removed on both architectures.

## Usage

```sh
./reset-brew.sh --dry-run   # show what would be removed
./reset-brew.sh             # actually remove it
```

This is destructive and not reversible — always run `--dry-run` first on a
machine you care about.
