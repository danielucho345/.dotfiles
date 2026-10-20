#!/usr/bin/env bash
# Read-only checks: this must run before packages or any user files change.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=false
SKIP_ACTIVITYWATCH=false
while (($#)); do
  case "$1" in
    --force) FORCE=true; shift ;;
    --skip)
      (($# >= 2)) || { echo "--skip requires a package name" >&2; exit 2; }
      [[ "$2" != activitywatch-bin ]] || SKIP_ACTIVITYWATCH=true
      shift 2 ;;
    *) echo "Usage: $0 [--force] [--skip <package>]..." >&2; exit 2 ;;
  esac
done
fail() { echo "Complete configuration preflight: $*" >&2; exit 1; }
for command in git jq omarchy omarchy-shell pacman yay sudo rg perl; do
  command -v "$command" >/dev/null || fail "$command is required; install it before complete setup"
done
if ! $SKIP_ACTIVITYWATCH; then
  for command in cargo rustc cc make pkg-config systemctl; do
    command -v "$command" >/dev/null || fail "$command is required for ActivityWatch; install Rust and build tools with: sudo pacman -S --needed rust base-devel (or omit tracking with --skip activitywatch-bin)"
  done
  cargo --version >/dev/null && rustc --version >/dev/null \
    || fail "Rust toolchain is unavailable; configure Rust first or use --skip activitywatch-bin"
fi

submodule_status="$(git -C "$ROOT" submodule status --recursive)" \
  || fail "cannot inspect submodules; run from a Git checkout of .dotfiles"
while IFS= read -r status; do
  [[ -n "$status" ]] || continue
  # An omitted ActivityWatch integration does not need its source checkout.
  if $SKIP_ACTIVITYWATCH && [[ "$status" == *" awatcher"* ]]; then continue; fi
  [[ "${status:0:1}" != - ]] \
    || fail "uninitialized submodule: $status; run: git -C '$ROOT' submodule update --init --recursive"
  [[ "${status:0:1}" != U ]] || fail "submodule has unresolved conflicts: $status"
done <<<"$submodule_status"

required_files=(defaults/omarchy-shell.json defaults/monitor-backgrounds.json
  install/packages.conf install/plugins.json config/nvim/init.lua config/oh-my-posh/custom.json
  config/hypr/hyprland-overrides.lua bin/wallpaper-monitor bin/hypr-window-switcher
  config/omarchy/plugins/daniel.window-switcher/manifest.json
  config/omarchy-wallpapers/plugins/daniel.background/manifest.json)
if ! $SKIP_ACTIVITYWATCH; then
  required_files+=(awatcher/Cargo.toml config/systemd/user/aw-server-rust.service config/systemd/user/aw-awatcher.service)
fi
for file in "${required_files[@]}"; do
  [[ -f "$ROOT/$file" ]] || fail "missing $file; restore repository files and initialize required submodules with: git -C '$ROOT' submodule update --init --recursive"
done
for script in install-dotfiles.sh install-hyprland-overrides.sh desktop-generator.sh \
  install/install-shell.sh install/install-desktop-settings.sh install/install-wallpapers.sh \
  install/install-plugins.sh install/install-activitywatcher.sh; do
  [[ -x "$ROOT/$script" ]] || fail "missing or non-executable installer: $ROOT/$script"
done
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ "$config_root" == "$HOME/.config" ]] \
  || fail "Hyprland setup currently uses \$HOME/.config; unset XDG_CONFIG_HOME or set it to $HOME/.config"
[[ -f "$HOME/.config/hypr/hyprland.lua" || -f "$HOME/.config/hypr/hyprland.conf" ]] \
  || fail "Hyprland base configuration is missing; initialize your Omarchy desktop first"
[[ -d "$ROOT/config/omarchy-wallpapers/themes/tokyo-night-wallpapers/backgrounds" ]] \
  || fail "wallpaper sources are missing"
jq -e '.version == 1 and (.bar | type == "object") and (.idle | type == "object")' \
  "$ROOT/defaults/omarchy-shell.json" >/dev/null || fail "invalid desktop settings template"
plugin_args=(--check)
$FORCE && plugin_args+=(--force)
"$ROOT/install/install-plugins.sh" "${plugin_args[@]}"
echo "Complete configuration preflight passed."
