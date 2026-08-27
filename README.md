# OmarchFonts

Browse Omarchy fonts in a live preview grid, apply one with Activate, and install `.ttf` / `.otf` / `.zip` fonts into `~/.local/share/fonts` from the panel.

**Version:** 0.2.0

## What it does

- **Grid preview** — monospace fonts from `omarchy font list`, plus user-installed faces from `~/.local/share/fonts`
- **Activate on hover** — small Activate button (bottom-right); Enter also applies the selection
- **Format labels** — shows `ttf` / `otf` / etc. on each card
- **Add fonts** — Zenity file picker copies into `~/.local/share/fonts`, refreshes `fc-cache`, notifies, optionally auto-applies the first monospace family
- **Search** — filter by family name (`/` focuses the search field)

## Install

```bash
omarchy plugin add https://github.com/giodc/OmarchFonts.git --enable
```

## Install (local / development)

```bash
mkdir -p ~/.config/omarchy/plugins
ln -sfn "$(pwd)" ~/.config/omarchy/plugins/io.github.giodc.omarchfonts
omarchy plugin enable io.github.giodc.omarchfonts
omarchy-shell shell rescanPlugins
```

## How fonts work on Omarchy

| Step | Command / path |
|------|----------------|
| List monospace fonts | `omarchy font list` |
| Show active font | `omarchy font current` |
| Apply | `omarchy font set "Family Name"` |
| User-installed files | `~/.local/share/fonts` + `fc-cache -f` |

## Settings

| Key | Default | Meaning |
|-----|---------|---------|
| `previewText` | `Aa Bb 123` | Sample string on each card |
| `autoApplyOnInstall` | `true` | After install, set the first monospace family automatically |

## Remove

```bash
omarchy plugin remove io.github.giodc.omarchfonts
```
