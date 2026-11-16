# Finder Sidebar Custom Icons Utility

## Goal

Build a small macOS utility that lets you configure custom Finder sidebar icons at runtime.

The intended workflow is:

1. Choose a folder.
2. Choose an icon file.
3. Enable the mapping.
4. Finder shows the configured icon for that folder in the sidebar.

The utility should support multiple folder/icon mappings from a single application and Finder Sync extension.

---

## Why this is needed

Finder supports custom folder icons in normal Finder views, but those icons do not necessarily appear in the Favorites section of the sidebar.

Third-party utilities demonstrate that Finder sidebar icons can be customized, but for a work machine it may not be desirable or acceptable to install an opaque third-party application.

The objective is therefore to build a small, inspectable macOS application from source and run it locally.

---

## Recommended architecture

Use one macOS application containing one Finder Sync extension.

```text
Sidebar Icons.app
│
├── SwiftUI GUI
│   ├── Add Folder…
│   ├── Choose Icon…
│   ├── Remove
│   ├── Enable / Disable
│   └── Preview
│
├── Shared configuration
│   └── App Group / shared preferences
│
└── SidebarIconsFinderExtension.appex
    ├── Reads configured folders
    ├── Registers monitored roots
    └── Supplies the sidebar icon for each root
```

A single Finder Sync extension can monitor multiple folders. There is no need to create one extension per icon.

---

## Example runtime configuration

The application could display a table like this:

| Folder | Sidebar icon | Enabled |
|---|---|---|
| `~/dev` | Development Projects | Yes |
| `~/Cloud Shortcuts/AI` | AI Projects | Yes |
| `~/Cloud Shortcuts/QEC` | Engineering | Yes |

Internally, the configuration could be represented with a simple model such as:

```json
[
  {
    "folder": "/Users/me/dev",
    "icon": "dev.svg",
    "enabled": true
  },
  {
    "folder": "/Users/me/Cloud Shortcuts/AI",
    "icon": "ai.svg",
    "enabled": true
  }
]
```

The exact storage format is not important. A Codable Swift model stored in shared preferences or an App Group container is probably the cleanest implementation.

---

## Finder Sync root registration

The extension can rebuild the set of monitored folders from configuration.

Conceptually:

```swift
let enabledFolders: [URL] = configuration
    .filter { $0.enabled }
    .map { $0.folderURL }

FIFinderSyncController.default().directoryURLs = Set(enabledFolders)
```

This is the key reason one extension can handle many sidebar icons.

---

## GUI behavior

A minimal first version only needs a few actions.

### Add Folder

Use `NSOpenPanel` configured to select directories.

Suggested behavior:

- allow one folder at a time
- resolve and store the full path or bookmark
- reject duplicate mappings
- optionally show whether the folder currently exists

### Choose Icon

Use another `NSOpenPanel` for image selection.

Reasonable input formats:

- SVG
- PDF
- PNG with transparency

For sidebar use, simple monochrome or template-style artwork will generally work best visually.

The application should copy the chosen icon into its own Application Support or App Group directory rather than depending on the original file remaining in place.

### Enable / Disable

Each mapping should have an enabled flag so the user can temporarily remove a folder from the extension's monitored roots without deleting the configuration.

### Remove

Removing a mapping should only remove the utility's configuration. It must never rename, move, or delete the actual folder.

### Preview

Show a small sidebar-sized preview, ideally around the size Finder will render.

---

## Runtime icon handling: the main technical question

Before building the complete GUI, test whether Finder Sync accepts arbitrary runtime-loaded images for sidebar icons in the current macOS release.

There are two likely outcomes.

### Path A: arbitrary runtime images work

This is the ideal case.

The application copies the selected image into its shared container, the Finder Sync extension loads it into `NSImage`, and the extension supplies the corresponding icon for the monitored root.

If this works reliably, the entire application can remain on public Finder Sync APIs.

### Path B: Finder expects registered bundle resources

Older Finder Sync documentation emphasizes sidebar icons that are resources associated with the containing application.

If arbitrary runtime image files are not accepted or do not refresh reliably, use a hybrid approach:

- Finder Sync manages monitored folders and runtime configuration.
- A small local icon-registration mechanism associates each custom icon with Launch Services.
- Finder sidebar entries receive the corresponding icon override.

This moves part of the implementation into private or deprecated behavior, so it should be treated as unsupported and isolated behind a small adapter layer.

---

## Private Launch Services mechanism

Current sidebar-icon utilities indicate that Finder Favorites can carry a private property named approximately:

```text
com.apple.LSSharedFileList.OverrideIcon.OSType
```

The value is a four-character OSType code such as:

```text
D001
D002
D003
```

Finder can then ask Launch Services which icon is registered for that code.

A local helper bundle can register those icon types without needing to run as a normal application.

Conceptually:

```text
Folder A  -> D001 -> dev icon
Folder B  -> D002 -> AI icon
Folder C  -> D003 -> engineering icon
```

This is a private implementation detail and may change between macOS releases.

Do not make this the first implementation unless the public Finder Sync route cannot provide runtime-selected artwork.

---

## Avoid direct `.sfl4` database editing

Finder's sidebar/Favorites storage is private and has changed across macOS versions.

Even if direct editing of Finder's shared file list database is technically possible, it is the least desirable option because:

- Finder owns the file.
- the format is undocumented
- Finder may overwrite changes
- the format may change between releases
- corruption could affect all sidebar Favorites

Prefer Finder Sync or the Launch Services property approach instead.

---

## Custom folder icons versus sidebar icons

A folder can have a normal custom Finder icon and still require separate handling for its sidebar icon.

For example:

```text
~/dev
```

may have a custom folder icon resembling a macOS development-project folder, while the Finder sidebar still shows the generic Favorites folder glyph.

Treat these as two separate visual layers:

```text
Folder icon
    Used in Finder windows, path bars, icon/list views, etc.

Sidebar icon
    Used specifically by Finder's sidebar.
```

The utility should not modify the user's existing folder icon unless explicitly requested.

---

## Suggested data model

A simple Swift model could be:

```swift
struct SidebarIconMapping: Identifiable, Codable {
    var id: UUID
    var folderPath: String
    var iconFilename: String
    var enabled: Bool
}
```

For a more robust implementation, store a security-scoped bookmark or file bookmark rather than only a path.

Possible extended model:

```swift
struct SidebarIconMapping: Identifiable, Codable {
    var id: UUID
    var folderBookmark: Data
    var displayPath: String
    var iconFilename: String
    var enabled: Bool
}
```

---

## Shared configuration

The main application and Finder Sync extension need access to the same configuration.

An App Group is a natural choice.

Example concept:

```text
group.com.example.SidebarIcons
```

Store:

```text
Application Support/
    SidebarIcons/
        config.json
        Icons/
            <uuid>.png
            <uuid>.svg
            <uuid>.pdf
```

The app writes the configuration and assets.

The extension reads them.

---

## Updating the extension at runtime

When the user changes configuration, the app should signal the Finder Sync extension to reload.

Possible approaches include:

- shared preferences plus Darwin notification
- distributed notification where appropriate
- extension reload when Finder restarts
- lightweight polling only if absolutely necessary

The implementation should avoid a long-running helper daemon unless there is a concrete need for one.

---

## Refresh behavior

Finder may cache sidebar icons.

The utility may need a refresh action such as:

```text
Refresh Finder
```

Possible implementation:

```bash
killall Finder
```

This restarts Finder and is usually safe, but it should be explicit and user initiated rather than performed silently every time a mapping changes.

Ideally, first attempt any available extension refresh mechanism and only use Finder restart when necessary.

---

## Security and work-machine-friendly constraints

Keep the application intentionally boring.

Recommended constraints:

- no networking
- no telemetry
- no updater
- no login item unless required
- no privileged helper
- no root access
- no SIP changes
- no third-party runtime dependencies
- no Homebrew requirement
- no Python packages
- no file-system modification outside the app's own configuration and the selected Finder metadata behavior

The application should be completely buildable from source with Xcode.

---

## Suggested implementation phases

### Phase 1 — hard-coded proof of concept

Before writing the GUI, create a tiny Finder Sync extension with two hard-coded roots.

Example:

```text
~/dev
~/Cloud Shortcuts/AI
```

Give each a different bundled icon.

Prove that:

1. both roots appear with different sidebar icons
2. one extension can service both
3. Finder preserves the icons after restart
4. normal folder icons remain unchanged

This validates the basic architecture.

---

### Phase 2 — test runtime image loading

Replace one bundled icon with an image loaded from the App Group container.

This is the most important technical experiment.

If it works, the rest of the application is straightforward.

If it does not work, prototype the Launch Services override mechanism before spending time on the GUI.

---

### Phase 3 — minimal GUI

Build one SwiftUI window containing:

- mappings table
- Add Folder button
- Choose Icon button
- Remove button
- Enabled checkbox
- preview

At this stage, do not add preferences, launch-at-login behavior, or other convenience features.

---

### Phase 4 — persistence and refresh

Add:

- App Group storage
- persisted mappings
- copied icon assets
- extension notification/reload
- Finder refresh command if needed

---

### Phase 5 — polish

Optional improvements:

- drag-and-drop icon selection
- automatic conversion to sidebar-appropriate template artwork
- duplicate-path detection
- missing-folder warnings
- import/export configuration
- icon presets
- reset to default icon
- icon preview at multiple Finder sidebar sizes

---

## Suggested v1 scope

A useful first release should contain only:

```text
+ Add Folder
+ Pick Icon
+ Enable / Disable
+ Remove
+ Preview
+ Refresh Finder
```

That is enough to manage any number of mappings without turning the utility into a large project.

---

## Development-project icon use case

One initial mapping can be:

```text
Folder:
~/dev

Purpose:
Development projects backed by Git repositories

Sidebar icon concept:
Stacked project layers with a Git branch symbol
```

The normal Finder folder icon and the sidebar glyph can intentionally use related artwork while remaining separate resources.

For the sidebar version, prefer a simplified, high-contrast shape because Finder renders sidebar glyphs very small.

---

## Key design decision

The project should initially assume this hierarchy of preference:

```text
1. Public Finder Sync APIs
        ↓ if insufficient
2. Finder Sync + Launch Services icon override
        ↓ only as a last resort
3. Direct Finder sidebar database manipulation
```

This keeps the utility as maintainable and macOS-native as possible.

---

## Bottom line

The jump from a hard-coded Finder Sync extension to a configurable utility is relatively small.

The GUI and configuration storage are straightforward. The only part that needs an early proof of concept is whether the current macOS Finder Sync implementation accepts arbitrary runtime-selected icon files for sidebar roots.

Once that is proven, supporting two, three, or twenty icons is essentially the same problem.

The best first implementation milestone is therefore:

> Build one application with one Finder Sync extension, two monitored folders, two different icons, and then replace one bundled icon with a runtime-selected image.

Everything else can be layered on afterward.
