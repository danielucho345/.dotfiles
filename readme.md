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
./install-all.sh shell                # enable Oh My Posh in Bash and Zsh
./install-all.sh wallpapers           # install monitor-aware Omarchy wallpapers
./install-all.sh hyprland             # opt-in; installs version-aware overrides
./install-all.sh activitywatch        # install and enable local ActivityWatch tracking
./install-all.sh desktop-launchers    # backs up existing launchers
./install-all.sh postgresql           # separate stateful setup
./install-all.sh all                  # packages, dotfiles, launchers only
```

Every operation can be previewed with `--dry-run`. Scripts resolve paths from their own location, so they can be run from another directory.

`all` must be run as the normal user, without wrapping the command in `sudo`:

```bash
./install-all.sh --dry-run all
./install-all.sh all
```

The package operation requests `sudo` only when `pacman` needs it. Running the
whole installer with `sudo` changes `$HOME` to `/root`, installs user files for
the root account, and may cause AUR tools to refuse to run.

To omit a package and its matching desktop launcher temporarily without
changing `install/packages.conf`, use `--skip`. It can be repeated when more
than one package should be omitted:

```bash
./install-all.sh --dry-run --force --skip opera all
./install-all.sh --force --skip opera all
```

The skipped package remains in the manifest and can be installed later with
`./install-all.sh packages` after the package issue is resolved.

## Replacing existing dotfiles

The default `dotfiles` operation refuses an existing `~/.config/<package>`
directory so that it cannot overwrite personal configuration. To replace only
the files supplied by this repository, use:

```bash
./install-all.sh --dry-run --force dotfiles
./install-all.sh --force dotfiles
```

`--force` does not delete complete configuration directories. It backs up each
conflicting file under
`~/.local/state/dotfiles-backups/<timestamp>/` and then lets GNU Stow install
the repository files. Unrelated files and directories are preserved. This is
particularly important for `~/.config/systemd`: the repository provides the
ActivityWatch user units, but existing units such as `voxtype.service` and
`*.wants` links must remain untouched. Review the backup before removing it.

## Safety and rollback

- Existing dotfile conflicts stop installation; nothing is removed automatically.
- Existing desktop launchers and Hyprland configuration are copied to timestamped `.bak` files before replacement.
- The uninstall command is report-only because package ownership cannot safely be inferred from shell scripts:

```bash
./uninstall-all.sh
```

- Never delete PostgreSQL data to undo setup.
- Omarchy-owned files under `/usr/share/omarchy/` are never modified.

## Monitor-specific wallpapers

The wallpaper operation installs the curated images, the `daniel.background`
Omarchy plugin, and the `wallpaper-monitor` command. The plugin is a user-owned
clone of Omarchy's background service, so Omarchy Shell, theme transitions, the
global wallpaper picker, and the lock-screen fallback continue to work.
The curated images are linked into
`~/.config/omarchy/backgrounds/tokyo-night/`; they extend the stock Tokyo Night
theme instead of appearing as a separate wallpaper-only theme.

```bash
./install-all.sh --dry-run wallpapers
./install-all.sh wallpapers
wallpaper-monitor select          # choose a connected monitor, then an image
wallpaper-monitor select DP-1     # choose an image for a known output
wallpaper-monitor clear DP-1      # return that output to the global background
wallpaper-monitor apply           # reload saved assignments into Omarchy Shell
hyprctl monitors                  # inspect connector names
```

Assignments are stored outside Git in
`~/.local/state/omarchy/monitor-backgrounds.json`. Missing images and unknown
outputs fall back to Omarchy's current global background. `Super+Ctrl+Space`
keeps the global picker; after installing the Hyprland overrides,
`Super+Ctrl+Shift+Space` opens the monitor-aware picker.

If installation occurs outside a running desktop session, enable the plugin
after logging in:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable daniel.background
```

Recovery is `omarchy plugin disable daniel.background`, which restores the
built-in `omarchy.background` service. After major Omarchy updates, compare
the dotfiles clone with
`/usr/share/omarchy/shell/plugins/background/Background.qml` and merge relevant
upstream fixes before re-enabling it.

## Hyprland notes

Hyprland overrides are opt-in. Current Omarchy installations source
`hyprland-overrides.lua`; legacy `hyprland.conf` installations continue to use
`hyprland-overrides.conf`. The legacy overrides assume monitors named `DP-1`
and `DP-2`, and optional commands such as `ddcutil`, `grim`, `slurp`,
`wl-copy`, and ActivityWatch. Review the applicable override before enabling
it on different hardware. The installer checks the existing config, avoids
duplicate source lines, creates a backup, and validates with `hyprctl reload`
and `hyprctl configerrors` when a Hyprland session is available.

## Shell environment and Oh My Posh

```bash
export PATH="$HOME/.cargo/bin:$PATH"
export TCL_LIBRARY=/usr/lib/tcl8.6
export TK_LIBRARY=/usr/lib/tk8.6
```

`./install-all.sh all` installs and configures Oh My Posh automatically. It adds a marked, repeatable block to `~/.bashrc` and, when relevant, `~/.zshrc`, using `~/.config` paths so it works after cloning elsewhere. Missing Oh My Posh or configuration files are ignored so shell startup remains usable. Run `./install-all.sh --dry-run shell` to preview changes.

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
