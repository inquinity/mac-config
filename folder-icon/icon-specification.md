# Icon specification: what to create for each folder

**Feature**: 004-icon-groups (target 0.3.0) | **Based on**: the spike in [research.md](research.md),
macOS 27.2.1 (26B131)

Each mapped folder gets an **icon group**: one **sidebar glyph** (drawn outline blue, like the
system Favorites) and, optionally, **folder art** (the folder's own full-colour Finder icon). What
you create depends on whether the Mac that builds the glyph has Xcode.

## At a glance

| # | Resource | Workflow 1 (Xcode) | Workflow 2 (no Xcode) | Where it shows |
|---|----------|--------------------|-----------------------|----------------|
| 1 | Sidebar glyph | **Create**: an outline SVG (filled paths) | **Choose**: an SF Symbol name | Finder sidebar, outline blue |
| 2 | Glyph name | **Choose**: a short name | — (the SF Symbol name is the name) | Inside the registry's `Assets.car` |
| 3 | Folder art, master | **Create** (optional): full-colour, 1024 × 1024 | Same | Finder windows, Get Info, Dock, open panels |
| 4 | Folder art, small sizes | **Create** (optional): hand-tuned 16 and 32 pt | Same | Finder list and column views, sidebar-size previews |

Skip 3 and 4 and the folder keeps its normal blue folder icon in Finder windows; only the sidebar
changes. Setting the folder's Finder icon is an opt-in per folder (it writes a hidden `Icon\r`
file into the folder; see "Side effects").

## 1. Sidebar glyph (Workflow 1: you draw it)

One SVG file, for example `glyph.svg`.

| Requirement | Detail | Why |
|-------------|--------|-----|
| Format | SVG made only of **filled `<path>` elements** | The wizard wraps paths into Apple's symbol template; `actool` builds glyphs from fill geometry |
| No strokes | Convert strokes to shapes before exporting: Illustrator **Object › Path › Outline Stroke**, Figma **Outline stroke**, Sketch **Layer › Convert to Outlines**, Affinity **Expand Stroke**, Inkscape **Path › Stroke to Path** | Stroke-only art has no fill and is refused |
| No text, images, gradients or masks | Convert text to outlines; flatten everything to paths | Only path geometry is used |
| Colour | Any single fill colour; it is ignored | The sidebar tints the glyph with the accent colour |
| Holes | Use even-odd fill (`fill-rule="evenodd"`) or separate inner paths | Rings, outlines and cut-outs |
| Canvas | A `viewBox`, ideally **square** (for example `0 0 100 100`), art filling it with a little padding | The art is scaled to the glyph box by the `viewBox` height |
| Proportions | Width up to about 1.25 × height | Wider art draws smaller in the sidebar's square slot |
| Line weight | Outlines and gaps at least **8 % of the canvas height** (8 units on a 100-unit canvas) | The glyph is drawn at about 16–20 points; thinner lines blur or vanish |
| Detail | Few, bold shapes; no fine text or texture | Same reason |
| Weights | One drawing is enough | The app uses the same geometry for the light, regular and heavy weights (at least `Regular-M` is required) |
| Should match | The outline counterpart of the folder art (3) | So the sidebar and Finder windows read as the same icon |

Tip: Apple's free **SF Symbols** app is a good reference for line weight and size, and can show
whether a glyph sits well next to the system symbols.

## 2. Glyph name (Workflow 1)

| Requirement | Detail |
|-------------|--------|
| Characters | Lowercase letters, digits, dots and hyphens, for example `dev.folder` or `git-repo` |
| Unique | Not used by another of your glyphs |
| Note | The app adds a version suffix internally, so changing a glyph never shows a stale cached one |

## 1. Sidebar glyph (Workflow 2: you choose it)

| Requirement | Detail |
|-------------|--------|
| SF Symbol name | Any symbol name available on the Mac, for example `hammer`, `externaldrive`, `doc.text` |
| Finding names | The SF Symbols app (free from Apple), or the app's search box with a live tinted preview |
| Nothing to create | No files, no Xcode |

## 3. Folder art, master (optional, both workflows)

One full-colour image, for example `icon.png`, `icon.pdf` or `icon.svg`.

| Requirement | Detail | Why |
|-------------|--------|-----|
| Format | **PNG** with transparency at **1024 × 1024 px**, or a vector **PDF** or **SVG** | The app renders every icon size (16 to 512 pt, at 1x and 2x) from it |
| Shape | **Square**, art centred, transparent background | Non-square art is fitted into the square and looks small; the preview warns |
| Colour space | sRGB (or Display P3) | |
| Style | Full colour; designed to read at 32 pt as well as 512 pt | Finder shows it from list rows (16 pt) to Quick Look (512 pt) |

## 4. Folder art, small sizes (optional, both workflows)

For crisp small sizes, hand-tuned versions that replace the rendered ones. Either individual PNGs
or a standard macOS `.iconset` folder:

| File (in an `.iconset`) | Pixels | Used for |
|-------------------------|--------|----------|
| `icon_16x16.png` | 16 × 16 | List and column views (1x) |
| `icon_16x16@2x.png` | 32 × 32 | List and column views (Retina) |
| `icon_32x32.png` | 32 × 32 | Get Info, small icon view (1x) |
| `icon_32x32@2x.png` | 64 × 64 | Get Info, small icon view (Retina) |
| `icon_128x128.png`, `@2x` | 128, 256 | Icon view |
| `icon_256x256.png`, `@2x` | 256, 512 | Large icon view |
| `icon_512x512.png`, `@2x` | 512, 1024 | Quick Look, gallery |

Any size you don't provide is rendered from the master (3). A complete `.iconset` needs no master.

## Suggested layout per folder

```text
<name>/                     for example dev/
├── glyph.svg               1  sidebar glyph (Workflow 1; omit for an SF Symbol)
├── icon.png                3  folder art master, 1024 × 1024 (or icon.pdf / icon.svg)
└── icon.iconset/           4  optional hand-tuned sizes (icon_16x16.png …)
```

The wizard asks for the glyph name (2), or the SF Symbol name in Workflow 2.

## What the app makes from them (for reference)

| From | The app creates (in its container) | Shown by |
|------|------------------------------------|----------|
| 1 + 2 | A symbol template, compiled with `actool` into a combined `Assets.car` in a new versioned registry bundle | Finder sidebar (outline blue) |
| SF Symbol name | A registry type naming the symbol (no `Assets.car` needed) | Finder sidebar (outline blue) |
| 3 (+ 4) | A full `.icns` (16–512 pt, 1x and 2x) | The folder's Finder icon, via `NSWorkspace.setIcon` |

## Side effects of the folder art (opt-in)

- A hidden `Icon\r` file appears in the folder, and the folder's custom-icon flag is set. Remove
  and Reset All delete both, but only if the folder's icon is still the one the app set.
- The folder's modification time changes when the icon is set and when it is removed.
- In a git repository, `git status` shows `Icon\r` as untracked; add `Icon?` to your global
  gitignore. Sync services (iCloud Drive, Dropbox, OneDrive) copy the file to other Macs.
- A folder under `~/Documents` or `~/Desktop` may make macOS ask for access the first time.
- A folder that already has a custom icon is left alone unless you explicitly replace it.
