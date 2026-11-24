# intel/

Tools for Intel Macs, which Homebrew 7 no longer supports.

## install-tools.sh

Installs the inquinity utilities without brew. It reads each cask in
[inquinity/homebrew-tap](https://github.com/inquinity/homebrew-tap) (the source
of truth for version, URL, SHA-256 and minimum macOS) and installs the app into
`/Applications`. A version bump in the tap is picked up on the next run; nothing
here needs to change.

| Tool | Minimum macOS | Notes |
|---|---|---|
| `yatu` | 13 (Ventura) | Finder terminal button; preferred |
| `openinterminal-lite-inquinity` | 12 (Monterey) | Used only when macOS is too old for Yatu |
| `qltextview` | 26 (Tahoe) | |
| `belvedere` | 26 (Tahoe) | |

Minimums come from each cask's `depends_on macos:`, so the table can drift;
`--list` shows what applies to the Mac you are on. Tools the OS cannot run are
skipped with a message, not treated as failures. Nothing outside these four
casks is ever installed.

```sh
intel/install-tools.sh --list       # what would be installed or skipped here
intel/install-tools.sh --dry-run    # same; nothing downloaded
intel/install-tools.sh              # asks for confirmation, then installs
intel/install-tools.sh --yes        # no prompt (what update.sh uses)
intel/install-tools.sh --only belvedere
```

`scripts/update.sh` runs it with `--yes` on Intel Macs in place of the brew step.
The script refuses to run on Apple Silicon; use brew there.

### What it checks before installing

1. SHA-256 of the download matches the cask.
2. The app has an x86_64 slice (`file`, because `lipo` needs the command line tools).
3. `codesign --verify --deep --strict` passes.
4. `spctl` reports a notarized Developer ID build.
5. The Team ID matches the pinned value, where one is pinned. Only `belvedere`
   (`45GJWJVQN2`) is pinned so far; for the others the Team ID is printed. Add
   the others to `expected_team_id` in the script once confirmed.

A failure at any step leaves the existing install untouched and the state file
unchanged. Installed versions are recorded in
`~/.config/mac-config/intel-tools.state`.

Yatu's Finder extension must be switched on by hand; the cask's caveats are
printed after install.

### Trust model

The cask is read from the tap's `main` branch at run time, so the tap is
trusted for the version, URL and hash. Notarization, the signature, and the
Team ID pin are independent checks on the artifact itself.

## test-install-tools.sh

Offline tests using fixture casks and a temporary applications folder. They
cover OS selection (including macOS 10.15 and 11), the up-to-date skip,
`--dry-run`, an unreachable tap, and that a SHA-256 mismatch installs nothing.
The signing checks need a real notarized app and are not covered offline.
