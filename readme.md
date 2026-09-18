# Omarchy dotfiles

Safe, opt-in personal configuration for Omarchy 4.0.4. Existing user configuration is treated as authoritative: the scripts do not edit `/usr/share/omarchy/` and do not delete existing `~/.config` content.

## Before you begin

Review the scripts and run a dry run first:

```bash
./install-all.sh --list
./install-all.sh --dry-run all
```

The scripts install Arch/AUR packages, optionally link configuration with GNU Stow, optionally source Hyprland overrides, and install user desktop launchers. Package installation requires `sudo`; AUR installation requires `yay`.

## Operations

```bash
./install-all.sh packages             # explicit package manifest
./install-all.sh dotfiles             # refuses existing config conflicts
./install-all.sh hyprland             # opt-in; backs up hyprland.conf
./install-all.sh activitywatch        # install and enable local ActivityWatch tracking
./install-all.sh desktop-launchers    # backs up existing launchers
./install-all.sh postgresql           # separate stateful setup
./install-all.sh all                  # packages, dotfiles, launchers only
```

Every operation can be previewed with `--dry-run`. Scripts resolve paths from their own location, so they can be run from another directory.

## Safety and rollback

- Existing dotfile conflicts stop installation; nothing is removed automatically.
- Existing desktop launchers and Hyprland configuration are copied to timestamped `.bak` files before replacement.
- The uninstall command is report-only because package ownership cannot safely be inferred from shell scripts:

```bash
./uninstall-all.sh
```

- Never delete PostgreSQL data to undo setup.
- Omarchy-owned files under `/usr/share/omarchy/` are never modified.

## Hyprland notes

Hyprland overrides are opt-in. The current overrides assume monitors named `DP-1` and `DP-2`, and optional commands such as `ddcutil`, `grim`, `slurp`, `wl-copy`, and ActivityWatch. Review `hyprland-overrides.conf` before enabling it on different hardware. The installer checks the existing config, avoids duplicate source lines, creates a backup, and validates with `hyprctl configerrors` when possible.

## Shell environment examples

```bash
eval "$(oh-my-posh init bash --config /home/daniel/.dotfiles/config/oh-my-posh/custom.json)"
export PATH="$HOME/.cargo/bin:$PATH"
export TCL_LIBRARY=/usr/lib/tcl8.6
export TK_LIBRARY=/usr/lib/tk8.6
```

## Validation

Run shell syntax checks before committing changes:

```bash
find . -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Use ShellCheck when available. Test installation behavior with dry runs and a disposable home/config directory before applying changes to a live Omarchy session.

## ActivityWatch on Hyprland

ActivityWatch is an explicit opt-in operation. The integration installs the `activitywatch-bin` AUR package, builds the pinned `aw-watcher-window-hyprland` submodule into `~/.local/bin`, and enables three user services: `aw-server-rust`, `aw-watcher-afk`, and `aw-watcher-window-hyprland`.

The prototype tracks idle/active status and the focused Hyprland application, window, and workspace locally. Browser URL tracking is intentionally not enabled. ActivityWatch data is stored under `~/.local/share/activitywatch`; configuration is under `~/.config/activitywatch`; logs are under `~/.cache/activitywatch`.

Preview the operation with `./install-all.sh --dry-run activitywatch`. Check it with `systemctl --user status aw-server-rust aw-watcher-afk aw-watcher-window-hyprland` and `journalctl --user -u aw-watcher-window-hyprland`. The local ActivityWatch API is available at `http://127.0.0.1:5600`.

To stop collection, run `systemctl --user disable --now aw-server-rust aw-watcher-afk aw-watcher-window-hyprland`. No browser watcher or remote synchronization is configured.
