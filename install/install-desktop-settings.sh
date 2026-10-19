#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/defaults/omarchy-shell.json"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
DRY_RUN=false
FORCE=false
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    *) echo "Usage: $0 [--dry-run] [--force]" >&2; exit 2 ;;
  esac
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
jq -e 'type == "object" and .version == 1
  and (.bar | type) == "object" and (.idle | type) == "object"' "$TEMPLATE" >/dev/null \
  || { echo "Invalid desktop settings template: $TEMPLATE" >&2; exit 1; }

current='{"version":1,"plugins":[]}'
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  jq -e 'type == "object" and .version == 1' "$TARGET" >/dev/null \
    || { echo "Invalid shell config: $TARGET; repair it before installing settings." >&2; exit 1; }
  current="$(cat "$TARGET")"
fi
merged="$(jq --slurpfile template "$TEMPLATE" '.bar = $template[0].bar | .idle = $template[0].idle' <<<"$current")"
if jq -e --argjson merged "$merged" '. == $merged' <<<"$current" >/dev/null && [[ ! -L "$TARGET" ]]; then
  echo "Desktop settings already installed."
  exit 0
fi
if [[ -e "$TARGET" || -L "$TARGET" ]] && ! $FORCE; then
  echo "conflict: existing shell settings differ or are symlinked: $TARGET" >&2
  echo "Preview --dry-run --force desktop-settings, then use --force to back up and replace managed settings." >&2
  exit 1
fi
if $DRY_RUN; then
  echo "Would back up existing $TARGET and install bar/idle settings, preserving unrelated fields."
  exit 0
fi
mkdir -p "$(dirname "$TARGET")"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  backup="$(mktemp -d "${TARGET}.bak.$(date +%Y%m%d-%H%M%S).XXXXXX")"
  cp -a -- "$TARGET" "$backup/shell.json"
  # Keep the dereferenced contents too when converting a link to a live file.
  [[ ! -L "$TARGET" ]] || cp -L -- "$TARGET" "$backup/shell.contents.json"
  echo "Backed up shell config to $backup"
fi
tmp="$(mktemp "$(dirname "$TARGET")/.shell.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
printf '%s\n' "$merged" > "$tmp"
if [[ -e "$TARGET" ]]; then chmod --reference="$TARGET" "$tmp"; else chmod 600 "$tmp"; fi
mv -fT -- "$tmp" "$TARGET"
echo "Desktop settings installed; Omarchy Shell hot-reloads bar and idle settings."
