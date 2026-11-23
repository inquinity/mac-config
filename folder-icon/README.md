# Finder folder and sidebar icon assets

The SharePoint concept pairs two documents with a three-node sharing mark. Its blue folder, rounded shape, and line weight follow the existing `macOS-dev-folder-icon.png`. The dev sidebar glyph simplifies the existing stacked Git artwork to a branch inside a folder.

| Folder | Finder icon | Sidebar icon |
| --- | --- | --- |
| `~/dev` | `dev-folder.png`, `dev-folder.icns` | `dev-sidebar.svg`, `dev-sidebar.png` |
| `~/SharePoint` | `sharepoint-folder.png`, `sharepoint-folder.icns` | `sharepoint-sidebar.svg`, `sharepoint-sidebar.png` |

The 1024 × 1024 folder PNGs have transparent padding. Each `.icns` contains 16, 32, 128, 256, 512, and 1024 pixel representations. Sidebar PNGs are 256 × 256 pixels with transparent backgrounds; SVGs are the editable vector sources. Both sidebar glyphs use `#0875ec`, which a Finder Sync extension can also treat as template artwork if it controls tinting.

To apply the normal Finder folder icons, run `swift apply-folder-icons.swift --dry-run` here, then `swift apply-folder-icons.swift`. macOS creates or updates the special invisible `Icon\r` file and custom-icon Finder metadata inside each target folder. That file is per-folder metadata and should not be copied into this Git repository. The script does not change Favorites sidebar icons.

The separate Favorites icons belong in the Finder Sync extension described in `Finder_Sidebar_Custom_Icons_Utility.md`. macOS does not automatically use the folder's custom icon in Favorites, so `.icns` and `Icon\r` alone cannot guarantee the requested sidebar appearance.
