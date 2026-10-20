#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/desktop-apps/WhatsApp.desktop"
TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
TARGET="$TARGET_DIR/WhatsApp.desktop"
DRY_RUN=false
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$SOURCE"
fi
if $DRY_RUN; then
  echo "Would install $SOURCE -> $TARGET (requires chromium)"
  exit 0
fi
command -v chromium >/dev/null 2>&1 || {
  echo "chromium is required; install it with: sudo pacman -S --needed chromium" >&2
  exit 1
}
if [[ ! -L "$TARGET" ]] && cmp -s -- "$SOURCE" "$TARGET"; then
  echo "WhatsApp launcher is already installed."
  exit 0
fi
mkdir -p "$TARGET_DIR"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  backup="$(mktemp -d "$TARGET.bak.XXXXXXXX")"
  cp -a -- "$TARGET" "$backup/WhatsApp.desktop"
  echo "Backed up existing launcher to $backup/WhatsApp.desktop"
fi
cp --remove-destination -- "$SOURCE" "$TARGET"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$TARGET_DIR" >/dev/null 2>&1 || true
fi
echo "Installed WhatsApp without GPU acceleration. Link it with the QR code on first launch."
