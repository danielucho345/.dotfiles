# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

### MY CUSTOM CONFIG
export PATH="$HOME/.cargo/bin:$PATH"

# Ensure Alacritty uses the custom configuration
export GH_CONFIG_DIR=~/.config/gh

export XDG_CONFIG_HOME="$HOME/.dotfiles"

# Source Oh My Posh from dotfiles
if [ -d "$HOME/.dotfiles" ]; then
  if [ -n "$ZSH_VERSION" ]; then
    eval "$(oh-my-posh init zsh --config /home/daniel/.dotfiles/oh_my_posh/.config/oh_my_posh/custom.json)"
  elif [ -n "$BASH_VERSION" ]; then
    eval "$(oh-my-posh init bash --config /home/daniel/.dotfiles/oh_my_posh/.config/oh_my_posh/custom.json)"
  fi
fi

alias nvimconfig="nvim ~/.config/nvim/init.lua"

export PATH="$HOME/.local/bin:$PATH"

export PATH="/opt/nvim/bin:$PATH"

export XDG_CONFIG_HOME="$HOME/.config"

export TMUX_CONF="$HOME/.config/tmux/tmux.conf"
