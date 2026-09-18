#!/usr/bin/env bash
_dotfiles_oh_my_posh_init() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}/oh-my-posh/custom.json"
  command -v oh-my-posh >/dev/null 2>&1 || return 0
  [[ -r "$config" ]] || return 0
  eval "$(oh-my-posh init "${1:-bash}" --config "$config")"
}
_dotfiles_oh_my_posh_init "${ZSH_VERSION:+zsh}"
unset -f _dotfiles_oh_my_posh_init
