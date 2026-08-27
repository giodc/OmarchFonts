# OmarchFonts

Browse Omarchy monospace fonts in a live preview grid, apply one with a click, and install new `.ttf` / `.otf` / `.zip` fonts into `~/.local/share/fonts` from the panel — no manual copy or terminal `omarchy font set` required.

## What it does

- **Grid preview** — every monospace font from `omarchy font list`, rendered with your sample text
- **One-click apply** — runs `omarchy font set` (terminals + fontconfig monospace + shell restart)
- **Add fonts** — Zenity file picker copies into `~/.local/share/fonts`, refreshes `fc-cache`, then optionally applies the first monospace family
- **Search** — filter by family name (`/` focuses the search field)
- **Keyboard** — arrows move the selection, Enter applies, Esc closes

## Install (from this folder while developing)

```bash
mkdir -p ~/.config/omarchy/plugins
ln -sfn "$(pwd)" ~/.config/omarchy/plugins/io.github.giodc.omarchfonts
omarchy plugin enable io.github.giodc.omarchfonts
# if the shell is already running:
omarchy-shell shell rescanPlugins
```

Then place the widget on the bar (Settings → Bar, or edit `~/.config/omarchy/shell.json`), or summon it:

```bash
omarchy-shell shell summon io.github.giodc.omarchfonts
```

## Install (from git, once published)

```bash
omarchy plugin add https://github.com/giodc/OmarchFonts.git --enable
```

## How fonts work on Omarchy

| Step | Command / path |
|------|----------------|
| List monospace fonts | `omarchy font list` |
| Show active font | `omarchy font current` |
| Apply | `omarchy font set "Family Name"` |
| User-installed files | `~/.local/share/fonts` + `fc-cache -f` |

OmarchFonts wraps that flow. Package-based Nerd Fonts from the Omarchy menu (`omarchy install font …`) still work; this plugin is for browsing what you already have and dropping in font files.

## Settings

| Key | Default | Meaning |
|-----|---------|---------|
| `previewText` | `Aa Bb 123` | Sample string on each card |
| `autoApplyOnInstall` | `true` | After install, set the first monospace family automatically |

## Remove

```bash
omarchy plugin remove io.github.giodc.omarchfonts
```

Or delete `~/.config/omarchy/plugins/io.github.giodc.omarchfonts` and remove the bar entry from `shell.json`.
