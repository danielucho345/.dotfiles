#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_CONFIG="$HOME/.config/hypr/bindings.lua"
LUA_OVERRIDES="$HOME/.config/hypr/hyprland-overrides.lua"
LEGACY_CONFIG="$HOME/.config/hypr/hyprland.conf"
LEGACY_OVERRIDES="$ROOT/hyprland-overrides.conf"
HELPER_SOURCE="$ROOT/bin/hypr-window-switcher"
HELPER_TARGET="$HOME/.local/bin/hypr-window-switcher"
PLUGIN_ID="daniel.window-switcher"
PLUGIN_SOURCE="$ROOT/config/omarchy/plugins/$PLUGIN_ID"
PLUGIN_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
if [[ -f "$LUA_CONFIG" ]]; then
  CONFIG="$LUA_CONFIG"
  OVERRIDES="$LUA_OVERRIDES"
  line='dofile(os.getenv("HOME") .. "/.config/hypr/hyprland-overrides.lua")'
elif [[ -f "$LEGACY_CONFIG" ]]; then
  CONFIG="$LEGACY_CONFIG"
  OVERRIDES="$LEGACY_OVERRIDES"
  line="source = $OVERRIDES"
else
  echo "Hyprland config not found: $LUA_CONFIG or $LEGACY_CONFIG" >&2
  exit 1
fi
[[ -f "$OVERRIDES" ]] || { echo "Overrides file not found: $OVERRIDES; stow the hypr package first" >&2; exit 1; }

[[ -x "$HELPER_SOURCE" ]] || { echo "Window-switcher helper is missing or not executable: $HELPER_SOURCE" >&2; exit 1; }

check_link() {
  local source="$1" target="$2"
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then return; fi
  if [[ -e "$target" || -L "$target" ]]; then
    echo "conflict: existing path will not be replaced: $target" >&2
    exit 1
  fi
}
link_file() {
  local source="$1" target="$2"
  echo "==> Installing $target"
  if [[ -L "$target" ]]; then echo "    already linked"; return; fi
  if $DRY_RUN; then
    echo "    would link $source"
  else
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
  fi
}

# Check every destination before changing config or creating either link.
check_link "$HELPER_SOURCE" "$HELPER_TARGET"
check_link "$PLUGIN_SOURCE" "$PLUGIN_TARGET"
command -v omarchy >/dev/null || { echo "Omarchy is required" >&2; exit 1; }
command -v omarchy-shell >/dev/null || { echo "Omarchy Shell is required" >&2; exit 1; }
omarchy plugin validate "$PLUGIN_SOURCE"

if grep -Fqx "$line" "$CONFIG"; then
  echo "Override already sourced"
else
  if $DRY_RUN; then
    echo "Would back up and append: $line"
  else
    backup="$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$CONFIG" "$backup"
    printf '\n%s\n' "$line" >> "$CONFIG"
    echo "Backed up Hyprland config to $backup"
  fi
fi

link_file "$HELPER_SOURCE" "$HELPER_TARGET"
link_file "$PLUGIN_SOURCE" "$PLUGIN_TARGET"
if $DRY_RUN; then
  echo "Would rescan Omarchy plugins and enable $PLUGIN_ID"
else
  omarchy-shell shell rescanPlugins
  omarchy plugin enable "$PLUGIN_ID"
fi

if ! $DRY_RUN && command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload
  hyprctl configerrors || { echo "Hyprland reported configuration errors; restore ${backup:-the latest backup}" >&2; exit 1; }
fi
echo "Hyprland overrides installed."
