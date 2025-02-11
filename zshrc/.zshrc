eval "$(oh-my-posh init zsh --config ~/.dotfiles/oh_my_posh/.config/oh_my_posh/custom.json)" 

eval "$(/opt/homebrew/bin/brew shellenv)"

alias nvimconfig="nvim ~/.config/nvim/init.lua"

export PATH="$HOME/.local/bin:$PATH"

export PATH="/opt/nvim/bin:$PATH"

export XDG_CONFIG_HOME="$HOME/.config"

export TMUX_CONF="$HOME/.config/tmux/tmux.conf"
