#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER_DIR="$ROOT/aw-watcher-window-hyprland"
INSTALL_ROOT="$HOME/.local"
WATCHER_BIN="$INSTALL_ROOT/bin/aw-watcher-window-hyprland"
UNIT_DIR="$ROOT/config/systemd/user"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

require_command() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }

require_command yay
require_command cargo
require_command hyprctl
require_command systemctl
[[ -d "$WATCHER_DIR/.git" || -f "$WATCHER_DIR/.git" ]] || {
  echo "ActivityWatch Hyprland watcher submodule is not initialized: $WATCHER_DIR" >&2
  exit 1
}
for unit in aw-server-rust.service aw-watcher-afk.service aw-watcher-window-hyprland.service; do
  [[ -f "$UNIT_DIR/$unit" ]] || { echo "Missing service unit: $UNIT_DIR/$unit" >&2; exit 1; }
done

if $DRY_RUN; then
  echo "+ yay -S --needed --noconfirm activitywatch-bin"
  echo "+ cargo install --locked --path $WATCHER_DIR --root $INSTALL_ROOT"
  echo "+ systemctl --user mask --now app-aw\\x2dqt@autostart.service"
  echo "+ systemctl --user daemon-reload"
  echo "+ systemctl --user enable --now aw-server-rust.service aw-watcher-afk.service aw-watcher-window-hyprland.service"
  exit 0
fi

yay -S --needed --noconfirm activitywatch-bin
mkdir -p "$INSTALL_ROOT"
cargo install --locked --path "$WATCHER_DIR" --root "$INSTALL_ROOT"

# The package's desktop autostart launches duplicate AFK and X11 window
# watchers. This setup manages the server and Hyprland watchers as user units.
systemctl --user mask --now 'app-aw\x2dqt@autostart.service'
systemctl --user link \
  "$UNIT_DIR/aw-server-rust.service" \
  "$UNIT_DIR/aw-watcher-afk.service" \
  "$UNIT_DIR/aw-watcher-window-hyprland.service"
systemctl --user daemon-reload
systemctl --user enable --now \
  aw-server-rust.service \
  aw-watcher-afk.service \
  aw-watcher-window-hyprland.service

echo "ActivityWatch and the Hyprland watcher are installed and running."
