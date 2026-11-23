# Finder icon groups

These are the inputs for the **Xcode available** workflow in [icon-specification.md](icon-specification.md). Import each `glyph.svg` into the sidebar icon wizard, enter its glyph name, and optionally import its `icon.png` as folder art.

| Folder | Glyph name | Filled-path sidebar SVG | 1024 px folder master |
| --- | --- | --- | --- |
| `~/dev` | `dev.folder` | [`dev/glyph.svg`](dev/glyph.svg) | [`dev/icon.png`](dev/icon.png) |
| `~/SharePoint` | `sharepoint.folder` | [`sharepoint/glyph.svg`](sharepoint/glyph.svg) | [`sharepoint/icon.png`](sharepoint/icon.png) |
| `~/mac-config` | `mac.settings` | [`mac-settings/glyph.svg`](mac-settings/glyph.svg) | [`mac-settings/icon.png`](mac-settings/icon.png) |

Each SVG contains only filled paths in a square viewBox. Its colour is a placeholder; Finder supplies the blue sidebar tint. The optional 16 and 32 pt folder images are omitted because the wizard renders them from each master.

The SharePoint master follows the folder already shown by Finder: a blue folder with the `cloud.fill` symbol. Finder stores that customization in `com.apple.icon.folder#S`, so there is no original image file to copy. The earlier linked-documents concept is preserved as `sharepoint-documents-*` in this directory. The older `dev-sidebar.svg` and `sharepoint-documents-sidebar.svg` files are previews from the first concept and are **not** the filled-path wizard inputs.

The supplied `apply-folder-icons.swift` tool is separate from the icon-group wizard. It applies the root-level `.icns` files to normal Finder folder views; it does not set Favorites sidebar icons. It now skips folders with existing custom icon metadata unless run with `--replace-existing`. Run `swift apply-folder-icons.swift --dry-run` to preview its action. The wizard should be used for the sidebar glyphs.
