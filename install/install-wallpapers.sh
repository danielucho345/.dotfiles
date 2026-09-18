#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_ROOT="$ROOT/config/omarchy-wallpapers"
PACKAGE_DIR="$PACKAGE_ROOT/themes"
PACKAGE="tokyo-night-wallpapers"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/themes/tokyo-night-wallpapers"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

[[ -d "$PACKAGE_DIR/$PACKAGE/backgrounds" ]] || {
  echo "Missing wallpaper package: $PACKAGE_DIR/$PACKAGE/backgrounds" >&2
  exit 1
}

if ! $DRY_RUN && ! command -v stow >/dev/null 2>&1; then
  echo "stow is required; install it first" >&2
  exit 1
fi

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

if $DRY_RUN; then echo "Wallpaper dry run complete; no files changed."; else echo "Wallpaper package installed; no wallpaper was selected."; fi
