# Omarchy dotfiles

Safe, opt-in personal configuration for Omarchy 4.0.4. Existing user configuration is treated as authoritative: the scripts do not edit `/usr/share/omarchy/` and do not delete existing `~/.config` content.

## Before you begin

Review the scripts and run a dry run first:

```bash
./install-all.sh --list
./install-all.sh --dry-run all
```

The scripts install Arch/AUR packages, optionally link configuration with GNU Stow, optionally restore desktop settings and source Hyprland overrides, and install user desktop launchers. Package installation requires `sudo`; AUR installation requires `yay`.

## Operations

```bash
./install-all.sh packages             # explicit package manifest
./install-all.sh dotfiles             # refuses existing config conflicts
./install-all.sh shell                # enable Oh My Posh in Bash and Zsh
./install-all.sh desktop-settings     # restore tracked bar and idle preferences
./install-all.sh wallpapers           # install monitor-aware Omarchy wallpapers
./install-all.sh hyprland             # opt-in; installs version-aware overrides
./install-all.sh activitywatch        # install and enable local ActivityWatch tracking
./install-all.sh plugins              # restore the declared plugin files and enabled states
./install-all.sh desktop-launchers    # backs up existing launchers
./install-all.sh whatsapp             # isolated WhatsApp Web without GPU acceleration
./install-all.sh postgresql           # separate stateful setup
./install-all.sh all                  # packages, dotfiles, shell, desktop launchers only
./install-all.sh --complete-config all # also restore desktop, tracking, and plugins
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

## Complete configuration

To restore the maintained desktop setup in one invocation:

```bash
git submodule update --init --recursive
./install-all.sh --dry-run --complete-config all
./install-all.sh --complete-config all

# If the preview reports managed configuration conflicts:
./install-all.sh --dry-run --complete-config --force all
./install-all.sh --complete-config --force all
```

`--complete-config` is accepted only with `all`. It runs packages, dotfiles,
shell setup, desktop settings, wallpapers, Hyprland overrides, ActivityWatch,
plugins, and desktop launchers, in that order. Plain `all` keeps the shorter
sequence. PostgreSQL and the older standalone installers remain separate;
untracked application data and account sessions are not restored.
Complete setup defers background/window-switcher activation to the plugin
step, so their state changes share its shell configuration backup. Their
standalone installers continue to activate them immediately.

Complete setup assumes an existing Omarchy desktop with a Hyprland base
configuration under `~/.config/hypr`. It checks required sources and initialized
submodules before installing packages or changing configuration. Git, jq,
Omarchy Shell, pacman/yay, sudo, ripgrep, and Perl must already be available.
ActivityWatch also needs a working Rust toolchain, C build tools, pkg-config,
and user systemd. Install missing build prerequisites with
`sudo pacman -S --needed rust base-devel`; existing Rust installations can be
used. Submodules may require access to the private repositories declared in
`.gitmodules`. Complete setup currently requires `XDG_CONFIG_HOME` to be unset
or equal to `$HOME/.config`, matching the Hyprland installer.

`--force` remains a separate choice. It permits the backed-up replacements
supported by dotfiles, desktop settings, and plugins; wallpaper and Hyprland
link conflicts still stop installation. Each failure names its operation;
fix that issue and repeat the command. With
`--skip activitywatch-bin`, both its package installation and its tracking
setup are omitted. Dry runs show operations and plugin revisions without
downloads, package installation, or configuration changes.

### Declared Omarchy plugins

`install/plugins.json` is the source of truth for these five plugin states:

| Plugin | Desired state | Source |
| --- | --- | --- |
| `daniel.background` | Enabled | Tracked wallpaper plugin |
| `daniel.window-switcher` | Enabled | Tracked window-switcher plugin |
| `custom.media` | Enabled | Pinned Music Flow Git revision |
| `crmne.hyprmoncfg` | Enabled | Pinned hyprmoncfg Git revision |
| `jankeesvw.notification-center` | Enabled | Pinned Notification Center Git revision |

The standalone `./install-all.sh plugins` operation restores these files and
states too. It does not install the wallpaper assets, Hyprland bindings, or
their helper commands; complete setup includes those separate operations.
Third-party sources are fetched at exact commits into
`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/omarchy-plugins/<id>/<revision>`
and linked into `~/.config/omarchy/plugins/`. Upstream installation scripts
are never executed. Optional plugin runtime dependencies are not installed
by this operation. Change the manifest's pin
deliberately when updating a plugin.

An existing clean Git checkout with the same origin and revision is reused.
Other existing plugin paths cause a conflict; `--force` moves them into a
unique `~/.local/state/dotfiles-backups/plugins.*` directory before replacement.
A modified managed cache is refused even with `--force`; move it aside before
retrying. Shared configuration/plugin directories must be real directories,
so adding a plugin cannot write through a directory symlink into the checkout.

The plugin operation rescans the running shell, waits for discovery, and
enforces the declared states using Omarchy commands while preserving unrelated
plugins. Before state changes, an existing shell configuration is backed up
under `shell.json.bak.*`. Repeating an already matching installation does not
change plugin states or create another backup. Keep the checkout and managed
plugin sources at their installed paths so their symlinks remain valid.

Without a running Omarchy Shell, files are installed and activation is reported
as **pending**. Finish after login with:

```bash
./install-all.sh plugins
```

To roll back a replaced plugin, move its new link aside and restore the
original from the printed backup path. Restore shell configuration from its
printed backup when reverting state changes, then rescan with
`omarchy-shell shell rescanPlugins`.

## Replacing existing dotfiles

The default `dotfiles` operation accepts compatible existing directories and
repository links, preserves unrelated files, and refuses conflicting files. To replace only the files supplied by this repository, use:

```bash
./install-all.sh --dry-run --force dotfiles
./install-all.sh --force dotfiles
```

`--force` does not delete complete configuration directories. It backs up each
conflicting file under
`~/.local/state/dotfiles-backups/<timestamp>/` and then lets GNU Stow install
the repository files. Unrelated files and directories are preserved. This is
also safe for existing directory symlinks: the installer does not move files
through them, and converts matching absolute links to relative links that Stow
recognizes. An already linked package root is left alone. This is
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

## Restore desktop settings explicitly

`all` leaves desktop configuration opt-in. Restore a desktop in this order,
previewing each command with `--dry-run` first:

```bash
./install-all.sh --force dotfiles
./install-all.sh desktop-settings
./install-all.sh wallpapers
./install-all.sh hyprland
```

For a focused update on an existing machine, replace the first command with:

```bash
./install-dotfiles.sh --force --only hypr --only alacritty --only tmux
```

The tracked Hyprland input settings select US and Spanish (Spain), with Left
Ctrl + Left Alt switching. Alacritty preserves Shift + Enter as ESC followed
by carriage return. The tmux config tracks the active Omarchy bindings and
appearance without TPM/session-restoration plugins.

`defaults/omarchy-shell.json` holds the selected bar layout and idle settings
(150 seconds for the screensaver, 300 seconds for locking). These currently
match the packaged defaults, but tracking them pins the chosen behavior.
`desktop-settings` merges only `bar` and `idle` into a normal live
`~/.config/omarchy/shell.json`; plugin registrations and other fields survive.
It refuses differing settings or a symlink unless `--force` is supplied, which
backs up the original before replacing it. Invalid JSON must be repaired first.
Identical settings are a no-op. Omarchy Shell hot-reloads the file; later UI
changes stay local until deliberately copied back into the template.

Rollback: restore the conflicting dotfiles from the printed
`dotfiles-backups` directory, restore `shell.json` from its printed `.bak.*`
directory, and restore the backed-up Hyprland main/bindings files from their
`dotfiles.bak.*` directory. Reload Hyprland and check `hyprctl configerrors`.
Restore wallpaper state from its `.bak.*` directory when one was created,
then run `wallpaper-monitor apply`. Keep the repository checkout at a permanent
path so live symlinks survive worktree cleanup.

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
`~/.local/state/omarchy/monitor-backgrounds.json`. The tracked
`defaults/monitor-backgrounds.json` uses portable filenames: DP-1 defaults to
sailboat beach and DP-2 to street shop atmosphere. Installation seeds only
missing output assignments using the installed background directory, preserving
all saved selections. Modified existing state is backed up and replaced
atomically; malformed state stops installation before assets are changed.
Missing images and unknown outputs fall back to Omarchy's current global background. `Super+Ctrl+Space`
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

Hyprland overrides are opt-in. Current Omarchy installations source the Stowed
`~/.config/hypr/hyprland-overrides.lua`; legacy `hyprland.conf` installations continue to use
`hyprland-overrides.conf`. The legacy overrides assume monitors named `DP-1`
and `DP-2`, and optional commands such as `ddcutil`, `grim`, `slurp`,
`wl-copy`, and ActivityWatch. Review the applicable override before enabling
it on different hardware. The installer normalizes the Lua override load to a single
`require("hypr.hyprland-overrides")` in the main config and removes old direct
loads from the main config and bindings file. It backs up all affected files
before editing them and validates with `hyprctl reload`
and `hyprctl configerrors` when a Hyprland session is available.

`./install-all.sh hyprland` also links `hypr-window-switcher` into
`~/.local/bin/`. `Super+E` opens a searchable list of windows on regular
workspaces. Each result includes its application/title, workspace, and monitor;
choosing it focuses that exact window, including when it is on another monitor.
Scratchpad windows are intentionally not listed because they do not have a
persistent monitor location.

To remove this feature, delete the `SUPER + E` binding from the applicable
override, then reload Hyprland. After confirming
`~/.local/bin/hypr-window-switcher` still resolves to this repository's
`bin/hypr-window-switcher`, remove that symlink with `unlink`.

## WhatsApp without GPU acceleration

Install only the WhatsApp launcher, leaving browser settings unchanged:

```bash
./install-all.sh --dry-run whatsapp
./install-all.sh whatsapp
# Or directly: ./install/install-whatsapp.sh
```

Chromium must already be installed (`sudo pacman -S --needed chromium`).
The launcher runs WhatsApp Web with `--disable-gpu` in its own data directory,
`${XDG_CONFIG_HOME:-$HOME/.config}/chromium-whatsapp`, so Google Meet can keep
using graphics acceleration in the usual browser. Link WhatsApp with the QR
code on first launch; later launches reuse that session. Close the old WhatsApp
window and reopen it from the application menu after installing.

The installer backs up an existing `WhatsApp.desktop` before replacing it;
reinstalling an identical launcher does nothing. `desktop-launchers` (and `all`)
also includes this launcher. No browser profiles or global GPU flags are changed.
To undo it, restore the backed-up launcher. The isolated WhatsApp data stays on
disk so it can be reused.

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

Run the disposable-home installer regression tests:

```bash
python3 tests/desktop-installers.py
python3 tests/complete-config.py
bash tests/hypr-window-switcher.sh
```

Use ShellCheck when available. Test installation behavior with dry runs and a disposable home/config directory before applying changes to a live Omarchy session.

## ActivityWatch on Hyprland

ActivityWatch is an explicit opt-in operation. The integration installs the `activitywatch-bin` AUR package, disables its duplicate desktop autostart, builds the pinned `awatcher` submodule without the optional GNOME/KDE integrations, and enables two user services: `aw-server-rust` and `aw-awatcher`.

`awatcher` uses Hyprland's native Wayland protocols to track idle/active status and the focused application and window. It writes new events to `aw-watcher-afk_<hostname>` and `aw-watcher-window_<hostname>`. The previous `aw-watcher-window-hyprland_<hostname>` and `aw-watcher-workspace-hyprland_<hostname>` buckets remain available as history but receive no new events. Browser URL tracking is intentionally not enabled. ActivityWatch data is stored under `~/.local/share/activitywatch`; configuration is under `~/.config/activitywatch`; logs are under `~/.cache/activitywatch`.

Preview the operation with `./install-all.sh --dry-run activitywatch`. Check it with `systemctl --user status aw-server-rust aw-awatcher` and `journalctl --user -u aw-awatcher`. The local ActivityWatch API is available at `http://127.0.0.1:5600`.

To stop collection, run `systemctl --user disable --now aw-server-rust aw-awatcher`. To uninstall the managed watcher, also run `systemctl --user unlink aw-awatcher.service`, remove `~/.local/bin/awatcher`, and optionally unmask `app-aw\x2dqt@autostart.service` if the packaged ActivityWatch desktop launcher should manage startup again. Existing ActivityWatch data is not removed. No browser watcher or remote synchronization is configured.
