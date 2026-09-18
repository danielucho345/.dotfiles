#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_CONFIG="$HOME/.config/hypr/bindings.lua"
LUA_OVERRIDES="$HOME/.config/hypr/hyprland-overrides.lua"
LEGACY_CONFIG="$HOME/.config/hypr/hyprland.conf"
LEGACY_OVERRIDES="$ROOT/hyprland-overrides.conf"
HELPER_SOURCE="$ROOT/bin/hypr-window-switcher"
HELPER_TARGET="$HOME/.local/bin/hypr-window-switcher"
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

link_helper() {
  echo "==> Checking window-switcher helper -> $HELPER_TARGET"
  if [[ -L "$HELPER_TARGET" && "$(readlink -f "$HELPER_TARGET")" == "$(readlink -f "$HELPER_SOURCE")" ]]; then
    echo "    already linked"
    return
  fi
  if [[ -e "$HELPER_TARGET" || -L "$HELPER_TARGET" ]]; then
    echo "conflict: existing path will not be replaced: $HELPER_TARGET" >&2
    exit 1
  fi
  if $DRY_RUN; then
    echo "    would link $HELPER_SOURCE"
  else
    mkdir -p "$(dirname "$HELPER_TARGET")"
    ln -s "$HELPER_SOURCE" "$HELPER_TARGET"
  fi
}

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

link_helper

if ! $DRY_RUN && command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload
  hyprctl configerrors || { echo "Hyprland reported configuration errors; restore ${backup:-the latest backup}" >&2; exit 1; }
fi
echo "Hyprland overrides installed."
