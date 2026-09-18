#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER_DIR="$ROOT/awatcher"
INSTALL_ROOT="$HOME/.local"
WATCHER_BIN="$INSTALL_ROOT/bin/awatcher"
LEGACY_WATCHER_BIN="$INSTALL_ROOT/bin/aw-watcher-window-hyprland"
UNIT_DIR="$ROOT/config/systemd/user"
USER_UNIT_DIR="$HOME/.config/systemd/user"
LEGACY_UNITS=(aw-watcher-afk.service aw-watcher-window-hyprland.service)
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

require_command() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }

[[ -d "$WATCHER_DIR/.git" || -f "$WATCHER_DIR/.git" ]] || {
  echo "awatcher submodule is not initialized: $WATCHER_DIR" >&2
  exit 1
}
for unit in aw-server-rust.service aw-awatcher.service; do
  [[ -f "$UNIT_DIR/$unit" ]] || { echo "Missing service unit: $UNIT_DIR/$unit" >&2; exit 1; }
done

if $DRY_RUN; then
  echo "+ yay -S --needed --noconfirm activitywatch-bin"
  echo "+ cargo install --locked --no-default-features --path $WATCHER_DIR --root $INSTALL_ROOT"
  echo "+ systemctl --user mask --now app-aw\\x2dqt@autostart.service"
  echo "+ systemctl --user link $UNIT_DIR/aw-server-rust.service $UNIT_DIR/aw-awatcher.service"
  echo "+ systemctl --user daemon-reload"
  echo "+ systemctl --user disable --now ${LEGACY_UNITS[*]}"
  echo "+ systemctl --user enable --now aw-server-rust.service aw-awatcher.service"
  echo "+ remove known obsolete unit symlinks and $LEGACY_WATCHER_BIN"
  exit 0
fi

require_command yay
require_command cargo
require_command systemctl

yay -S --needed --noconfirm activitywatch-bin
mkdir -p "$INSTALL_ROOT"
cargo install --locked --no-default-features --path "$WATCHER_DIR" --root "$INSTALL_ROOT"
[[ -x "$WATCHER_BIN" ]] || { echo "awatcher was not installed at $WATCHER_BIN" >&2; exit 1; }

# The package's desktop autostart launches duplicate legacy watchers. This
# setup manages the server and native Wayland watcher as user units instead.
systemctl --user mask --now 'app-aw\x2dqt@autostart.service'
systemctl --user link \
  "$UNIT_DIR/aw-server-rust.service" \
  "$UNIT_DIR/aw-awatcher.service"
systemctl --user daemon-reload

# Stop the legacy collectors only after the replacement has been built and
# linked. Missing legacy units are expected on clean and repeated installs.
for unit in "${LEGACY_UNITS[@]}"; do
  systemctl --user disable --now "$unit" 2>/dev/null || true
  if systemctl --user is-active --quiet "$unit"; then
    echo "ActivityWatch migration failed: legacy collector $unit is still active." >&2
    exit 1
  fi
done
systemctl --user enable --now \
  aw-server-rust.service \
  aw-awatcher.service

for unit in aw-server-rust.service aw-awatcher.service; do
  if ! systemctl --user is-active --quiet "$unit"; then
    echo "ActivityWatch migration failed: $unit is not active." >&2
    echo "The legacy unit definitions have not been removed from the repository." >&2
    exit 1
  fi
done

# Remove only artifacts owned by the retired integration. systemctl disable
# removes wants links; these direct links may remain from `systemctl link`.
for unit in "${LEGACY_UNITS[@]}"; do
  [[ -L "$USER_UNIT_DIR/$unit" ]] && rm -f "$USER_UNIT_DIR/$unit"
done
[[ -e "$LEGACY_WATCHER_BIN" ]] && rm -f "$LEGACY_WATCHER_BIN"
systemctl --user daemon-reload

echo "ActivityWatch and awatcher are installed and running."
