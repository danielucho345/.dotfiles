#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
usage() { cat <<EOF
Usage: $0 [--dry-run] [--complete-config] [--force] [--skip <package>]... [--list] <operation>
Operations: packages, dotfiles, shell, desktop-settings, wallpapers, hyprland, activitywatch, plugins, desktop-launchers, whatsapp, postgresql, all
--complete-config: with all only, also restore desktop settings, wallpapers,
                   Hyprland, ActivityWatch, and the declared plugins.
--force: separately allow supported configuration replacements with backups.
EOF
}
run() { if $DRY_RUN; then echo "+ $*"; else "$@"; fi; }
run_script() {
  local script="$1"
  if $DRY_RUN; then "$script" --dry-run; else "$script"; fi
}
run_script_with_skips() {
  local script="$1"
  local args=()
  $DRY_RUN && args+=(--dry-run)
  for package in "${SKIP_PACKAGES[@]}"; do
    args+=(--skip "$package")
  done
  "$script" "${args[@]}"
}
is_skipped() {
  local candidate
  for candidate in "${SKIP_PACKAGES[@]}"; do
    [[ "$candidate" == "$1" ]] && return 0
  done
  return 1
}

DRY_RUN=false
FORCE=false
COMPLETE_CONFIG=false
SKIP_PACKAGES=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --complete-config) COMPLETE_CONFIG=true; shift ;;
    --skip)
      (($# >= 2)) || { echo "--skip requires a package name" >&2; usage; exit 2; }
      SKIP_PACKAGES+=("$2")
      shift 2
      ;;
    --list) usage; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

op="${1:-}"; [[ -n "$op" ]] || { usage; exit 2; }
[[ $# == 1 ]] || { usage; exit 2; }
if $COMPLETE_CONFIG && [[ "$op" != all ]]; then
  echo "--complete-config is only valid with all" >&2
  exit 2
fi
trap 'status=$?; echo "Installation failed during operation: $op (exit $status)" >&2; exit "$status"' ERR
case "$op" in
  packages)
    pacman_packages=()
    aur_packages=()
    skipped_packages=()
    while IFS=: read -r source package; do
      [[ -z "$source" || "$source" == \#* ]] && continue
      if is_skipped "$package"; then
        skipped_packages+=("$package")
        continue
      fi
      case "$source" in
        pacman) pacman_packages+=("$package");;
        aur) aur_packages+=("$package");;
        *) echo "Unknown package source: $source" >&2; exit 1;;
      esac
    done < "$ROOT/install/packages.conf"
    if ((${#skipped_packages[@]})); then
      printf 'Skipping package(s): %s\n' "${skipped_packages[*]}"
    fi
    if ((${#pacman_packages[@]})); then
      command -v pacman >/dev/null || { echo "pacman is required" >&2; exit 1; }
      run sudo pacman -S --needed "${pacman_packages[@]}"
    fi
    if ((${#aur_packages[@]})); then
      command -v yay >/dev/null || { echo "yay is required" >&2; exit 1; }
      run yay -S --needed "${aur_packages[@]}"
    fi;;
  dotfiles)
    if $FORCE; then
      if $DRY_RUN; then "$ROOT/install-dotfiles.sh" --dry-run --force; else "$ROOT/install-dotfiles.sh" --force; fi
    else
      run_script "$ROOT/install-dotfiles.sh"
    fi;;
  shell) run_script "$ROOT/install/install-shell.sh";;
  desktop-settings)
    args=()
    $DRY_RUN && args+=(--dry-run)
    $FORCE && args+=(--force)
    "$ROOT/install/install-desktop-settings.sh" "${args[@]}";;
  plugins)
    args=()
    $DRY_RUN && args+=(--dry-run)
    $FORCE && args+=(--force)
    "$ROOT/install/install-plugins.sh" "${args[@]}";;
  wallpapers) run_script "$ROOT/install/install-wallpapers.sh";;
  hyprland) run_script "$ROOT/install-hyprland-overrides.sh";;
  activitywatch)
    if is_skipped activitywatch-bin; then
      echo "Skipping ActivityWatch setup (--skip activitywatch-bin)."
    else
      run_script "$ROOT/install/install-activitywatcher.sh"
    fi;;
  desktop-launchers) run_script_with_skips "$ROOT/desktop-generator.sh";;
  whatsapp) run_script "$ROOT/install/install-whatsapp.sh";;
  postgresql) run_script "$ROOT/install/install-postgresql.sh";;
  all)
    if $COMPLETE_CONFIG; then
      check_args=()
      $FORCE && check_args+=(--force)
      for package in "${SKIP_PACKAGES[@]}"; do check_args+=(--skip "$package"); done
      "$ROOT/install/check-complete-config.sh" "${check_args[@]}"
    fi
    forwarded=()
    $DRY_RUN && forwarded+=(--dry-run)
    $FORCE && forwarded+=(--force)
    for package in "${SKIP_PACKAGES[@]}"; do
      forwarded+=(--skip "$package")
    done
    steps=(packages dotfiles shell)
    if $COMPLETE_CONFIG; then
      steps+=(desktop-settings wallpapers hyprland)
      if is_skipped activitywatch-bin; then
        echo "Skipping ActivityWatch setup (--skip activitywatch-bin)."
      else
        steps+=(activitywatch)
      fi
      steps+=(plugins)
    fi
    steps+=(desktop-launchers)
    for step in "${steps[@]}"; do
      echo "==> Operation: $step"
      # The child labels failures with its specific operation; avoid a second
      # generic 'all' error and preserve its original exit status.
      if $COMPLETE_CONFIG && [[ "$step" == wallpapers || "$step" == hyprland ]]; then
        # Activate once, in the final plugin step, after it has backed up the
        # shell config. Standalone wallpaper/Hyprland operations still enable
        # their plugins immediately.
        if DOTFILES_DEFER_PLUGIN_ACTIVATION=true "$0" "${forwarded[@]}" "$step"; then :; else exit "$?"; fi
      else
        if "$0" "${forwarded[@]}" "$step"; then :; else exit "$?"; fi
      fi
    done
    if $COMPLETE_CONFIG; then
      echo "Complete configuration steps finished; review any pending plugin activation above."
    fi;;
  *) usage; exit 2;;
esac
