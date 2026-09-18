#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_CONFIG="$HOME/.config/hypr/bindings.lua"
LUA_OVERRIDES="$ROOT/hyprland-overrides.lua"
LEGACY_CONFIG="$HOME/.config/hypr/hyprland.conf"
LEGACY_OVERRIDES="$ROOT/hyprland-overrides.conf"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
if [[ -f "$LUA_CONFIG" ]]; then
  CONFIG="$LUA_CONFIG"
  OVERRIDES="$LUA_OVERRIDES"
  line="dofile(\"$OVERRIDES\")"
elif [[ -f "$LEGACY_CONFIG" ]]; then
  CONFIG="$LEGACY_CONFIG"
  OVERRIDES="$LEGACY_OVERRIDES"
  line="source = $OVERRIDES"
else
  echo "Hyprland config not found: $LUA_CONFIG or $LEGACY_CONFIG" >&2
  exit 1
fi
[[ -f "$OVERRIDES" ]] || { echo "Overrides file not found: $OVERRIDES" >&2; exit 1; }
if grep -Fqx "$line" "$CONFIG"; then echo "Override already sourced"; exit 0; fi
if $DRY_RUN; then echo "Would back up and append: $line"; exit 0; fi
backup="$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
cp -a -- "$CONFIG" "$backup"
printf '\n%s\n' "$line" >> "$CONFIG"
echo "Backed up Hyprland config to $backup"
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload
  hyprctl configerrors || { echo "Hyprland reported configuration errors; restore $backup" >&2; exit 1; }
fi
echo "Hyprland overrides installed."
