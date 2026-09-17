#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Repository package report (no packages will be removed):"
while IFS=: read -r source package; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  status=not-installed
  command -v pacman >/dev/null 2>&1 && pacman -Qi "$package" >/dev/null 2>&1 && status=installed
  printf '  %-7s %-28s %s\n' "$source" "$package" "$status"
done < "$ROOT/install/packages.conf"
echo "No uninstall operation is provided until package ownership can be tracked safely."
