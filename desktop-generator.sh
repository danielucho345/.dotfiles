#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$ROOT/desktop-apps"
TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }
[[ -d "$SOURCE_DIR" ]] || { echo "Missing directory: $SOURCE_DIR" >&2; exit 1; }
for file in "$SOURCE_DIR"/*.desktop; do
  [[ -f "$file" ]] || continue
  command -v desktop-file-validate >/dev/null 2>&1 && desktop-file-validate "$file"
  target="$TARGET_DIR/$(basename "$file")"
  if $DRY_RUN; then echo "Would install $file -> $target"; continue; fi
  mkdir -p "$TARGET_DIR"
  if [[ -e "$target" ]]; then cp -a -- "$target" "$target.bak.$(date +%Y%m%d-%H%M%S)"; fi
  cp -- "$file" "$target"
done
if ! $DRY_RUN && command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$TARGET_DIR" >/dev/null 2>&1 || true; fi
