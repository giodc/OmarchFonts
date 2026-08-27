#!/usr/bin/env bash
# OmarchFonts helpers — list / set / install fonts for Omarchy.
set -euo pipefail

FONTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
ACTION="${1:-}"

json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

family_from_file() {
  fc-query -f '%{family[0]}' "$1" 2>/dev/null | head -n1
}

spacing_from_file() {
  fc-query -f '%{spacing}' "$1" 2>/dev/null | head -n1
}

ensure_fonts_dir() {
  mkdir -p "$FONTS_DIR"
}

copy_font_file() {
  local src=$1
  local base dest
  base=$(basename -- "$src")
  dest="$FONTS_DIR/$base"
  if [[ -e $dest ]] && ! cmp -s -- "$src" "$dest"; then
    local stem ext i=1
    if [[ $base == *.* ]]; then
      ext=.${base##*.}
      stem=${base%.*}
    else
      ext=
      stem=$base
    fi
    while [[ -e $FONTS_DIR/${stem}-${i}${ext} ]]; do
      i=$((i + 1))
    done
    dest="$FONTS_DIR/${stem}-${i}${ext}"
  fi
  cp -f -- "$src" "$dest"
  printf '%s\n' "$dest"
}

# Prints one JSON object describing the installed file.
install_one_file() {
  local src=$1
  local installed_path family spacing mono=false
  case "${src,,}" in
    *.ttf|*.otf|*.ttc|*.otc|*.woff|*.woff2) ;;
    *)
      echo "skip non-font: $src" >&2
      return 1
      ;;
  esac
  installed_path=$(copy_font_file "$src")
  family=$(family_from_file "$installed_path")
  spacing=$(spacing_from_file "$installed_path")
  [[ $spacing == 100 ]] && mono=true
  if [[ -z $family ]]; then
    printf '{"path":"%s","family":"","monospace":false,"error":"could not read family"}' \
      "$(json_escape "$installed_path")"
    return 0
  fi
  printf '{"path":"%s","family":"%s","monospace":%s}' \
    "$(json_escape "$installed_path")" \
    "$(json_escape "$family")" \
    "$mono"
}

# Append installed JSON objects into the global INSTALL_RESULTS array.
INSTALL_RESULTS=()

install_zip() {
  local zip=$1
  local tmp extracted result
  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip is required to install font zip archives" >&2
    return 1
  fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/omarchfonts-XXXXXX")
  unzip -qq -o -j -- "$zip" \
    '*.ttf' '*.otf' '*.ttc' '*.otc' '*.woff' '*.woff2' \
    '*.TTF' '*.OTF' '*.TTC' '*.OTC' '*.WOFF' '*.WOFF2' \
    -d "$tmp" 2>/dev/null || true
  while IFS= read -r extracted; do
    [[ -z $extracted ]] && continue
    if result=$(install_one_file "$extracted"); then
      INSTALL_RESULTS+=("$result")
    fi
  done < <(find "$tmp" -type f \( \
    -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' -o \
    -iname '*.otc' -o -iname '*.woff' -o -iname '*.woff2' \
  \) -print)
  rm -rf -- "$tmp"
}

install_path() {
  local path=$1
  local result
  case "${path,,}" in
    *.zip)
      install_zip "$path" || true
      ;;
    *)
      if result=$(install_one_file "$path"); then
        INSTALL_RESULTS+=("$result")
      fi
      ;;
  esac
}

emit_installed() {
  printf '{"ok":true,"installed":['
  local i
  for i in "${!INSTALL_RESULTS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    printf '%s' "${INSTALL_RESULTS[$i]}"
  done
  printf ']}\n'
}

# Prefer a Regular/Roman face when listing a family's file format.
file_for_family() {
  local family=$1
  local file=""
  file=$(fc-list :family="$family" -f "%{file}\n" 2>/dev/null \
    | grep -iE 'regular|roman' | head -n1 || true)
  if [[ -z $file ]]; then
    file=$(fc-list :family="$family" -f "%{file}\n" 2>/dev/null | head -n1 || true)
  fi
  printf '%s' "$file"
}

# Unique lowercase extensions for a family (e.g. "ttf" or "ttf,otf").
exts_for_family() {
  local family=$1
  local -A exts=()
  local f base ext
  while IFS= read -r f; do
    [[ -z $f ]] && continue
    base=${f##*/}
    [[ $base == *.* ]] || continue
    ext=${base##*.}
    ext=${ext,,}
    case "$ext" in
      ttf|otf|ttc|otc|woff|woff2) exts[$ext]=1 ;;
    esac
  done < <(fc-list :family="$family" -f "%{file}\n" 2>/dev/null || true)
  local out="" e
  for e in ttf otf ttc otc woff woff2; do
    [[ -n ${exts[$e]+x} ]] || continue
    [[ -n $out ]] && out+=","
    out+=$e
  done
  printf '%s' "$out"
}

# True if family is in Omarchy's monospace list.
is_mono_family() {
  local family=$1
  fc-list :spacing=100 -f "%{family[0]}\n" 2>/dev/null | grep -Fqx -- "$family"
}

cmd_list() {
  local current
  current=$(omarchy-font-current 2>/dev/null || true)
  declare -A seen=()

  printf '['
  local first=true

  emit_row() {
    local family=$1 mono=$2 user=$3
    [[ -z $family ]] && return
    [[ -n ${seen[$family]+x} ]] && return
    seen[$family]=1
    case "${family,,}" in
      *emoji*|*signwriting*|omarchy) return ;;
    esac
    if $first; then first=false; else printf ','; fi
    local is_current=false
    [[ $family == "$current" ]] && is_current=true
    local ext
    ext=$(exts_for_family "$family")
    printf '{"family":"%s","current":%s,"monospace":%s,"user":%s,"ext":"%s"}' \
      "$(json_escape "$family")" "$is_current" "$mono" "$user" "$(json_escape "$ext")"
  }

  # Stock Omarchy monospace catalogue first.
  while IFS= read -r family; do
    emit_row "$family" true false
  done < <(omarchy-font-list 2>/dev/null || true)

  # User-installed faces from ~/.local/share/fonts (mono or proportional).
  if [[ -d $FONTS_DIR ]]; then
    while IFS= read -r family; do
      [[ -z $family ]] && continue
      local mono=false
      is_mono_family "$family" && mono=true
      emit_row "$family" "$mono" true
    done < <(
      find "$FONTS_DIR" -type f \( \
        -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' -o \
        -iname '*.otc' -o -iname '*.woff' -o -iname '*.woff2' \
      \) -print0 2>/dev/null \
        | xargs -0 -r -n1 fc-query -f '%{family[0]}\n' 2>/dev/null \
        | sort -u
    )
  fi

  printf ']\n'
}

cmd_current() {
  omarchy-font-current 2>/dev/null || true
  printf '\n'
}

cmd_set() {
  local family=${1-}
  if [[ -z $family ]]; then
    echo "Usage: fonts.sh set <font-name>" >&2
    exit 1
  fi
  omarchy-font-set "$family"
  printf '{"ok":true,"family":"%s"}\n' "$(json_escape "$family")"
}

cmd_pick_and_install() {
  ensure_fonts_dir
  if ! command -v zenity >/dev/null 2>&1; then
    echo '{"ok":false,"error":"zenity is required to pick font files"}'
    exit 1
  fi

  local files
  if ! files=$(zenity --file-selection --multiple --separator=$'\n' \
    --title="Install fonts" \
    --file-filter='Font files | *.ttf *.otf *.ttc *.otc *.woff *.woff2 *.zip' \
    --file-filter='All files | *' 2>/dev/null); then
    echo '{"ok":false,"cancelled":true}'
    exit 0
  fi

  INSTALL_RESULTS=()
  local line
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    install_path "$line"
  done <<< "$files"

  fc-cache -f "$FONTS_DIR" >/dev/null 2>&1 || true
  # Persist last result for debugging when the panel swallows stdout.
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
  mkdir -p "$state_dir"
  emit_installed | tee "$state_dir/omarchfonts-last-install.json"
}

cmd_install_paths() {
  ensure_fonts_dir
  shift || true
  INSTALL_RESULTS=()
  local path
  for path in "$@"; do
    [[ -z $path || ! -e $path ]] && continue
    install_path "$path"
  done
  fc-cache -f "$FONTS_DIR" >/dev/null 2>&1 || true
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
  mkdir -p "$state_dir"
  emit_installed | tee "$state_dir/omarchfonts-last-install.json"
}

case "$ACTION" in
  list) cmd_list ;;
  current) cmd_current ;;
  set) cmd_set "${2-}" ;;
  pick-install) cmd_pick_and_install ;;
  install-paths) cmd_install_paths "$@" ;;
  fonts-dir) printf '%s\n' "$FONTS_DIR" ;;
  -h|--help|help|"")
    cat <<'EOF'
Usage: fonts.sh <command>

Commands:
  list              JSON array of monospace fonts (omarchy font list)
  current           Current monospace font name
  set <name>        Apply font via omarchy-font-set
  pick-install      Zenity file picker → copy into ~/.local/share/fonts
  install-paths …   Install given .ttf/.otf/.zip paths (no dialog)
  fonts-dir         Print the user fonts directory
EOF
    ;;
  *)
    echo "Unknown command: $ACTION" >&2
    exit 1
    ;;
esac
