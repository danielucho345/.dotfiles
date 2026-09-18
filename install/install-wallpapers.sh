#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_ROOT="$ROOT/config/omarchy-wallpapers"
WALLPAPER_SOURCE="$PACKAGE_ROOT/themes/tokyo-night-wallpapers/backgrounds"
WALLPAPER_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/backgrounds/tokyo-night"
LEGACY_THEME_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/themes/tokyo-night-wallpapers"
PLUGIN_SOURCE="$PACKAGE_ROOT/plugins/daniel.background"
PLUGIN_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/daniel.background"
HELPER_SOURCE="$ROOT/bin/wallpaper-monitor"
HELPER_TARGET="$HOME/.local/bin/wallpaper-monitor"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

[[ -d "$WALLPAPER_SOURCE" ]] || {
  echo "Missing wallpaper package: $WALLPAPER_SOURCE" >&2
  exit 1
}
[[ -f "$PLUGIN_SOURCE/manifest.json" && -f "$PLUGIN_SOURCE/Background.qml" ]] || {
  echo "Missing monitor background plugin: $PLUGIN_SOURCE" >&2
  exit 1
}
[[ -f "$HELPER_SOURCE" ]] || {
  echo "Missing wallpaper helper: $HELPER_SOURCE" >&2
  exit 1
}

if ! command -v omarchy >/dev/null 2>&1; then
  echo "omarchy is required" >&2
  exit 1
fi

link_path() {
  local source="$1" target="$2" label="$3"

  echo "==> Checking $label -> $target"
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
    echo "    already linked"
    return
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    echo "conflict: existing path will not be replaced: $target" >&2
    exit 1
  fi
  if $DRY_RUN; then
    echo "    would link $source"
  else
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
  fi
}

remove_legacy_theme() {
  local legacy_backgrounds="$LEGACY_THEME_TARGET/backgrounds"

  [[ -e "$LEGACY_THEME_TARGET" || -L "$LEGACY_THEME_TARGET" ]] || return 0

  if [[ ! -d "$LEGACY_THEME_TARGET" || -L "$LEGACY_THEME_TARGET" ||
        ! -L "$legacy_backgrounds" ||
        "$(readlink -f "$legacy_backgrounds")" != "$(readlink -f "$WALLPAPER_SOURCE")" ||
        -n "$(find "$LEGACY_THEME_TARGET" -mindepth 1 -maxdepth 1 ! -name backgrounds -print -quit)" ]]; then
    echo "conflict: legacy theme contains user-owned content: $LEGACY_THEME_TARGET" >&2
    echo "Move it aside, then run the wallpaper installer again." >&2
    exit 1
  fi

  echo "==> Removing obsolete wallpaper-only theme -> $LEGACY_THEME_TARGET"
  if $DRY_RUN; then
    echo "    would remove the repository-owned backgrounds link and empty directory"
  else
    unlink "$legacy_backgrounds"
    rmdir "$LEGACY_THEME_TARGET"
  fi
}

link_wallpapers() {
  local source target legacy_target

  echo "==> Checking Tokyo Night user backgrounds -> $WALLPAPER_TARGET"
  if ! $DRY_RUN; then
    mkdir -p "$WALLPAPER_TARGET"
  fi

  while IFS= read -r -d '' source; do
    target="$WALLPAPER_TARGET/${source##*/}"
    legacy_target="$LEGACY_THEME_TARGET/backgrounds/${source##*/}"

    if [[ -L "$target" && "$(readlink "$target")" == "$legacy_target" ]]; then
      echo "==> Replacing obsolete wallpaper link -> $target"
      if $DRY_RUN; then
        echo "    would replace $legacy_target with $source"
        continue
      else
        unlink "$target"
      fi
    fi

    link_path "$source" "$target" "wallpaper ${source##*/}"
  done < <(
    find "$WALLPAPER_SOURCE" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
      -print0 | sort -z
  )
}

omarchy plugin validate "$PLUGIN_SOURCE"

repair_active_theme=false
if [[ -r "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name" ]] &&
   [[ "$(<"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme.name")" == "tokyo-night-wallpapers" ]]; then
  repair_active_theme=true
fi

remove_legacy_theme
link_wallpapers

link_path "$PLUGIN_SOURCE" "$PLUGIN_TARGET" "monitor background plugin"
link_path "$HELPER_SOURCE" "$HELPER_TARGET" "wallpaper-monitor command"

if $DRY_RUN; then
  echo "Wallpaper dry run complete; no files changed."
else
  if $repair_active_theme; then
    echo "==> Restoring the real Tokyo Night theme"
    omarchy theme set tokyo-night
  fi

  if omarchy-shell shell ping >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null
    discovered=false
    for _ in {1..40}; do
      if omarchy plugin list --json 2>/dev/null | jq -e \
        'any(.[]; .id == "daniel.background")' >/dev/null; then
        discovered=true
        break
      fi
      sleep 0.05
    done
    if $discovered; then
      omarchy plugin enable daniel.background >/dev/null
      echo "Wallpaper package installed and daniel.background enabled; no wallpaper was selected."
    else
      echo "Wallpaper package installed, but Omarchy Shell did not discover daniel.background." >&2
      echo "Run: omarchy-shell shell rescanPlugins && omarchy plugin enable daniel.background" >&2
      exit 1
    fi
  else
    echo "Wallpaper package installed; Omarchy Shell is not available."
    echo "When the desktop session is running, run:"
    echo "  omarchy-shell shell rescanPlugins && omarchy plugin enable daniel.background"
  fi
fi
