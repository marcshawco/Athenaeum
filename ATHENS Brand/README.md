# Athens — Brand kit

The mark is the capital letter **A** set in **Fraunces** italic, light, on a
softly-rounded ink square (~22 % corner radius). Quiet, literary, sized to
sit in a Mac dock without shouting.

## Tokens

| Role     | Hex       | Use                                              |
|----------|-----------|--------------------------------------------------|
| ink      | `#211F1B` | Primary field — the canonical mark                |
| paper    | `#FBFAF7` | Glyph colour against ink; default page background |
| forest   | `#243A2D` | Assistant context, dark inspector surfaces        |
| sage     | `#C8D4BE` | Glyph against forest                              |
| ruleS    | `#D8D2C4` | Hairlines on paper                                |

## Typography

- **Display / mark:** Fraunces (italic, weight 300; weight 400 below 32 px)
- **Wordmark:** Fraunces, weight 400, **letterspaced** (tracking ≈ 4–8 px)
- **System:** SF Pro Text / -apple-system
- **Mono:** ui-monospace, SF Mono, Menlo

## File index

### Vector masters
- `app-icon.svg` — 1024 master, ink primary
- `app-icon-forest.svg` — forest variant
- `app-icon-inverse.svg` — inverse (paper field, ink glyph)
- `favicon.svg` — 64, weight-bumped to 400 for legibility
- `wordmark.svg` — horizontal lockup with eyebrow

### Raster — ink (primary)
`app-icon-16.png` · `-24` · `-32` · `-48` · `-64` · `-128` · `-256` · `-512` · `-1024`

Sizes & uses:

| Size  | Use                                          |
|-------|----------------------------------------------|
| 16    | Favicon                                      |
| 24    | Toolbar                                      |
| 32    | Favicon @2x                                  |
| 48    | Finder list                                  |
| 64    | Finder grid, small                           |
| 128   | Finder grid large, App Store small           |
| 256   | Dock @2x, `apple-touch-icon`                 |
| 512   | App Store, marketing                         |
| 1024  | App Store master, source for `.icns`         |

### Raster — forest variant
`app-icon-128-forest.png` · `-256-forest` · `-512-forest` — for the assistant context and dark inspector chrome.

### Raster — inverse variant
`app-icon-128-inverse.png` · `-256-inverse` · `-512-inverse` — for printed exports and light backgrounds, with a hairline border.

### Source
- `athens-mark.jsx` — React component (`<AthensMark>`, `<AthensWordmark>`, `<AthensLockup>`)

## HTML wiring

```html
<link rel="icon" type="image/svg+xml" href="brand/favicon.svg" />
<link rel="icon" type="image/png" sizes="16x16" href="brand/app-icon-16.png" />
<link rel="icon" type="image/png" sizes="32x32" href="brand/app-icon-32.png" />
<link rel="apple-touch-icon" href="brand/app-icon-256.png" />
```

## Clear-space & don'ts

- Give the mark **¼ tile of clear space** on every side.
- **Minimum on-screen size:** 16 px. Below that, fall back to wordmark only.
- Don't stretch, tint, rotate, or add glow / outline / drop-shadow to the mark.
- The wordmark **ATHENS** is always letterspaced; never set it tight.

## Regenerating

The mark is system-typeset. To revise glyph, weight, or colour, edit
`athens-mark.jsx` (or the SVG masters) and re-rasterise to the size ladder.
