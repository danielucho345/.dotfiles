#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
DRY_RUN=false
FORCE=false
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    *) echo "Usage: $0 [--dry-run] [--force]" >&2; exit 2 ;;
  esac
done
[[ -d "$CONFIG_DIR" ]] || { echo "Missing config directory: $CONFIG_DIR" >&2; exit 1; }
if ! $DRY_RUN && ! command -v stow >/dev/null 2>&1; then
  echo "stow is required; install it first" >&2
  exit 1
fi

BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups/$(date +%Y%m%d-%H%M%S)"
conflicts=0

backup_conflict() {
  local package="$1"
  local relative="$2"
  local target_path="$3"
  local backup_relative="${relative:-_package_root}"
  local backup_path="$BACKUP_ROOT/$package/$backup_relative"

  if $DRY_RUN; then
    echo "    would back up $target_path -> $backup_path"
  else
    mkdir -p "$(dirname "$backup_path")"
    mv -- "$target_path" "$backup_path"
    echo "    backed up $target_path -> $backup_path"
  fi
}

prepare_force() {
  local package="$1"
  local package_path="$2"
  local target="$3"
  local source_entry relative target_entry

  if [[ -L "$target" || ( -e "$target" && ! -d "$target" ) ]]; then
    if [[ -L "$target" && "$(readlink -f "$target")" == "$package_path" ]]; then
      return
    fi
    backup_conflict "$package" "" "$target"
    return
  fi

  while IFS= read -r -d '' source_entry; do
    relative="${source_entry#"$package_path"/}"
    target_entry="$target/$relative"
    if [[ -L "$target_entry" ]]; then
      [[ "$(readlink -f "$target_entry")" == "$source_entry" ]] && continue
      backup_conflict "$package" "$relative" "$target_entry"
    elif [[ -e "$target_entry" && ! -d "$target_entry" ]]; then
      backup_conflict "$package" "$relative" "$target_entry"
    fi
  done < <(
    find "$package_path" -mindepth 1 -type d \
      ! -path "$package_path/.git" ! -path "$package_path/.git/*" -print0
  )

  while IFS= read -r -d '' source_entry; do
    relative="${source_entry#"$package_path"/}"
    target_entry="$target/$relative"
    if [[ -L "$target_entry" ]]; then
      [[ "$(readlink -f "$target_entry")" == "$source_entry" ]] && continue
      backup_conflict "$package" "$relative" "$target_entry"
    elif [[ -e "$target_entry" ]]; then
      backup_conflict "$package" "$relative" "$target_entry"
    fi
  done < <(
    find "$package_path" -mindepth 1 \
      ! -path "$package_path/.git" ! -path "$package_path/.git/*" \
      \( -type f -o -type l \) -print0
  )
}

for package_path in "$CONFIG_DIR"/*; do
  [[ -d "$package_path" ]] || continue
  package="$(basename "$package_path")"
  target="$HOME/.config/$package"
  echo "==> Checking $package -> $target"
  if $FORCE; then
    prepare_force "$package" "$package_path" "$target"
    if $DRY_RUN; then
      echo "    would create target and stow $package"
    else
      mkdir -p "$target"
      if ! stow --verbose --dir="$CONFIG_DIR" --target="$target" "$package"; then
        echo "    stow failed for $package" >&2
        conflicts=$((conflicts + 1))
      fi
    fi
    continue
  elif [[ -e "$target" || -L "$target" ]]; then
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
if $DRY_RUN; then
  if $FORCE; then echo "Force dry run complete; no files changed."; else echo "Dry run complete; no files changed."; fi
else
  if $FORCE; then echo "Dotfiles installed with backups; unrelated files were preserved."; else echo "Dotfiles installed safely."; fi
fi
