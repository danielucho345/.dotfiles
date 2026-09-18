#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_ROOT="$ROOT/config/omarchy-wallpapers"
PACKAGE_DIR="$PACKAGE_ROOT/themes"
PACKAGE="tokyo-night-wallpapers"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/themes/tokyo-night-wallpapers"
PLUGIN_SOURCE="$PACKAGE_ROOT/plugins/daniel.background"
PLUGIN_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/daniel.background"
HELPER_SOURCE="$ROOT/bin/wallpaper-monitor"
HELPER_TARGET="$HOME/.local/bin/wallpaper-monitor"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

[[ -d "$PACKAGE_DIR/$PACKAGE/backgrounds" ]] || {
  echo "Missing wallpaper package: $PACKAGE_DIR/$PACKAGE/backgrounds" >&2
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

if ! $DRY_RUN && ! command -v stow >/dev/null 2>&1; then
  echo "stow is required; install it first" >&2
  exit 1
fi
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

omarchy plugin validate "$PLUGIN_SOURCE"

echo "==> Checking wallpapers -> $TARGET"
if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
  echo "conflict: target exists and is not a directory: $TARGET" >&2
  exit 1
fi

if $DRY_RUN; then
  echo "    would stow $PACKAGE from $PACKAGE_DIR"
else
  mkdir -p "$TARGET"
  stow --verbose --dir="$PACKAGE_DIR" --target="$TARGET" "$PACKAGE"
fi

link_path "$PLUGIN_SOURCE" "$PLUGIN_TARGET" "monitor background plugin"
link_path "$HELPER_SOURCE" "$HELPER_TARGET" "wallpaper-monitor command"

if $DRY_RUN; then
  echo "Wallpaper dry run complete; no files changed."
elif omarchy-shell shell ping >/dev/null 2>&1; then
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
