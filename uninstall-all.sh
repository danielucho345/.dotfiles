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
echo "Oh My Posh shell integration report:"
for shell_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$shell_file" ]] && rg -q -F '# >>> dotfiles oh-my-posh >>>' "$shell_file"; then
    echo "  managed block present: $shell_file"
  else
    echo "  managed block absent:  $shell_file"
  fi
done
echo "To disable it, remove only the block between the dotfiles oh-my-posh markers."
