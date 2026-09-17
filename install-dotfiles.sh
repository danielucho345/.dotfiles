#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }
[[ -d "$CONFIG_DIR" ]] || { echo "Missing config directory: $CONFIG_DIR" >&2; exit 1; }
if ! $DRY_RUN && ! command -v stow >/dev/null 2>&1; then
  echo "stow is required; install it first" >&2
  exit 1
fi

conflicts=0
for package_path in "$CONFIG_DIR"/*; do
  [[ -d "$package_path" ]] || continue
  package="$(basename "$package_path")"
  target="$HOME/.config/$package"
  echo "==> Checking $package -> $target"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$package_path" ]]; then
      echo "    already linked"
    else
      echo "    conflict: existing configuration will not be deleted"
      conflicts=$((conflicts + 1))
    fi
    continue
  fi
  if $DRY_RUN; then
    echo "    would create target and stow $package"
  else
    mkdir -p "$target"
    if ! stow --verbose --dir="$CONFIG_DIR" --target="$target" "$package"; then
      echo "    stow failed for $package" >&2
      conflicts=$((conflicts + 1))
    fi
  fi
done

if (( conflicts > 0 )); then
  echo "Completed with $conflicts conflict(s). No existing configuration was deleted." >&2
  exit 1
fi
if $DRY_RUN; then echo "Dry run complete; no files changed."; else echo "Dotfiles installed safely."; fi
