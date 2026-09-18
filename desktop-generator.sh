#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$ROOT/desktop-apps"
TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DRY_RUN=false
SKIP_APPS=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --skip)
      (($# >= 2)) || { echo "--skip requires an application name" >&2; exit 2; }
      SKIP_APPS+=("$2")
      shift 2
      ;;
    *) echo "Usage: $0 [--dry-run] [--skip <application>]..." >&2; exit 2 ;;
  esac
done
[[ -d "$SOURCE_DIR" ]] || { echo "Missing directory: $SOURCE_DIR" >&2; exit 1; }
is_skipped() {
  local candidate
  for candidate in "${SKIP_APPS[@]}"; do
    [[ "$candidate" == "$1" ]] && return 0
  done
  return 1
}
for file in "$SOURCE_DIR"/*.desktop; do
  [[ -f "$file" ]] || continue
  app="$(basename "$file" .desktop)"
  if is_skipped "$app"; then
    echo "Skipping desktop launcher: $file"
    continue
  fi
  command -v desktop-file-validate >/dev/null 2>&1 && desktop-file-validate "$file"
  target="$TARGET_DIR/$(basename "$file")"
  if $DRY_RUN; then echo "Would install $file -> $target"; continue; fi
  mkdir -p "$TARGET_DIR"
  if [[ -e "$target" ]]; then cp -a -- "$target" "$target.bak.$(date +%Y%m%d-%H%M%S)"; fi
  cp -- "$file" "$target"
done
if ! $DRY_RUN && command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$TARGET_DIR" >/dev/null 2>&1 || true; fi
