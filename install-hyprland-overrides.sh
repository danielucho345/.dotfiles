#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_CONFIG="$HOME/.config/hypr/hyprland.lua"
LUA_BINDINGS="$HOME/.config/hypr/bindings.lua"
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
[[ $# == 0 || ( $# == 1 && "$DRY_RUN" == true ) ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }
if [[ -f "$LUA_CONFIG" ]]; then
  CONFIG="$LUA_CONFIG"
  OVERRIDES="$LUA_OVERRIDES"
  line='require("hypr.hyprland-overrides")'
elif [[ -f "$LEGACY_CONFIG" ]]; then
  CONFIG="$LEGACY_CONFIG"
  OVERRIDES="$LEGACY_OVERRIDES"
  line="source = $OVERRIDES"
else
  echo "Hyprland config not found: $LUA_CONFIG or $LEGACY_CONFIG" >&2
  exit 1
fi
if [[ "$CONFIG" == "$LUA_CONFIG" ]]; then
  [[ -f "$ROOT/config/hypr/hyprland-overrides.lua" ]] || { echo "Missing repository Lua overrides" >&2; exit 1; }
  if [[ ! -f "$OVERRIDES" ]] && ! $DRY_RUN; then
    echo "Overrides file not found: $OVERRIDES; stow the hypr package first" >&2
    exit 1
  fi
else
  [[ -f "$OVERRIDES" ]] || { echo "Overrides file not found: $OVERRIDES" >&2; exit 1; }
fi

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

# Only remove known direct loads of our own override module. Keep all other
# user code intact. The hypr.* module name is cleared by Omarchy's bootstrap
# on reload, unlike the old bare module name.
normalize_lua() {
  local source="$1" main="$2"
  awk -v main="$main" -v canonical="$line" '
    {
      compact = $0
      sub(/--.*/, "", compact)
      gsub(/[[:space:]]/, "", compact)
      gsub(/\047/, "\042", compact)
      if (compact == "require(\042hyprland-overrides\042)" ||
          compact == "require(\042hypr.hyprland-overrides\042)" ||
          compact == "dofile(os.getenv(\042HOME\042)..\042/.config/hypr/hyprland-overrides.lua\042)") next
      print
    }
    END { if (main == "true") print canonical }
  ' "$source"
}

staging="$(mktemp -d)"
trap 'rm -rf -- "$staging"' EXIT
changed=()
if [[ "$CONFIG" == "$LUA_CONFIG" ]]; then
  normalize_lua "$CONFIG" true > "$staging/main"
  cmp -s "$CONFIG" "$staging/main" || changed+=("$CONFIG")
  if [[ -f "$LUA_BINDINGS" ]]; then
    normalize_lua "$LUA_BINDINGS" false > "$staging/bindings"
    cmp -s "$LUA_BINDINGS" "$staging/bindings" || changed+=("$LUA_BINDINGS")
  fi
else
  # Deduplicate the exact repository source line in legacy configurations.
  awk -v canonical="$line" '$0 != canonical { print } END { print canonical }' "$CONFIG" > "$staging/main"
  cmp -s "$CONFIG" "$staging/main" || changed+=("$CONFIG")
fi

if ((${#changed[@]} == 0)); then
  echo "Override already sourced exactly once"
elif $DRY_RUN; then
  printf 'Would back up and normalize override loads in: %s\n' "${changed[@]}"
else
  # Back up every affected file before touching either source location.
  backup_dir="$(mktemp -d "$(dirname "$CONFIG")/dotfiles.bak.$(date +%Y%m%d-%H%M%S).XXXXXX")"
  for file in "${changed[@]}"; do
    cp -aL -- "$file" "$backup_dir/$(basename "$file")"
  done
  echo "Backed up Hyprland config to $backup_dir"
  for file in "${changed[@]}"; do
    candidate="$staging/main"
    [[ "$file" != "$LUA_BINDINGS" ]] || candidate="$staging/bindings"
    cat "$candidate" > "$file"
  done
fi

link_file "$HELPER_SOURCE" "$HELPER_TARGET"
link_file "$PLUGIN_SOURCE" "$PLUGIN_TARGET"
if [[ "${DOTFILES_DEFER_PLUGIN_ACTIVATION:-false}" == true ]]; then
  echo "Window-switcher plugin activation deferred to the plugins operation."
elif $DRY_RUN; then
  echo "Would rescan Omarchy plugins and enable $PLUGIN_ID"
else
  if omarchy-shell shell ping >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins
    omarchy plugin enable "$PLUGIN_ID"
  else
    echo "Omarchy Shell is unavailable; after login run: omarchy-shell shell rescanPlugins && omarchy plugin enable $PLUGIN_ID"
  fi
fi

if ! $DRY_RUN && command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload
  errors="$(hyprctl configerrors)" || { echo "Could not query Hyprland config errors" >&2; exit 1; }
  if [[ -n "$errors" && "$errors" != "ok" ]]; then
    echo "Hyprland reported configuration errors: $errors; restore ${backup_dir:-the latest backup}" >&2
    exit 1
  fi
fi
echo "Hyprland overrides installed."
