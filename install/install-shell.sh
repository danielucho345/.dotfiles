#!/usr/bin/env bash
set -Eeuo pipefail
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }
readonly START_MARKER="# >>> dotfiles oh-my-posh >>>"
readonly END_MARKER="# <<< dotfiles oh-my-posh <<<"
shell_file() {
  local file="$1"
  local block="$START_MARKER
# Managed by .dotfiles; safe to update automatically.
if [[ -r \"\$HOME/.config/shell/oh-my-posh.sh\" ]]; then
  source \"\$HOME/.config/shell/oh-my-posh.sh\"
fi
$END_MARKER"
  if [[ -f "$file" ]] && rg -q -F "$START_MARKER" "$file"; then
    echo "==> Updating Oh My Posh block in $file"
    $DRY_RUN || OMP_START="$START_MARKER" OMP_END="$END_MARKER" OMP_BLOCK="$block" perl -0pi -e 's/\Q$ENV{OMP_START}\E.*?\Q$ENV{OMP_END}\E/$ENV{OMP_BLOCK}/s' "$file"
  elif [[ -f "$file" ]]; then
    echo "==> Adding Oh My Posh block to $file"
    $DRY_RUN || printf '\n%s\n' "$block" >> "$file"
  else
    echo "==> Creating $file"
    $DRY_RUN || printf '%s\n' "$block" > "$file"
  fi
}
shell_file "$HOME/.bashrc"
if command -v zsh >/dev/null 2>&1 || [[ -e "$HOME/.zshrc" ]]; then shell_file "$HOME/.zshrc"; else echo "==> Skipping ~/.zshrc (zsh is not installed)"; fi
