#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
usage() { cat <<EOF
Usage: $0 [--dry-run] [--force] [--skip <package>]... [--list] <operation>
Operations: packages, dotfiles, shell, wallpapers, hyprland, activitywatch, desktop-launchers, postgresql, all
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

DRY_RUN=false
FORCE=false
SKIP_PACKAGES=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
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
case "$op" in
  packages)
    pacman_packages=()
    aur_packages=()
    skipped_packages=()
    is_skipped() {
      local candidate
      for candidate in "${SKIP_PACKAGES[@]}"; do
        [[ "$candidate" == "$1" ]] && return 0
      done
      return 1
    }
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
  wallpapers) run_script "$ROOT/install/install-wallpapers.sh";;
  hyprland) run_script "$ROOT/install-hyprland-overrides.sh";;
  activitywatch) run_script "$ROOT/install/install-activitywatcher.sh";;
  desktop-launchers) run_script_with_skips "$ROOT/desktop-generator.sh";;
  postgresql) run_script "$ROOT/install/install-postgresql.sh";;
  all)
    forwarded=()
    $DRY_RUN && forwarded+=(--dry-run)
    $FORCE && forwarded+=(--force)
    for package in "${SKIP_PACKAGES[@]}"; do
      forwarded+=(--skip "$package")
    done
    "$0" "${forwarded[@]}" packages
    "$0" "${forwarded[@]}" dotfiles
    "$0" "${forwarded[@]}" shell
    "$0" "${forwarded[@]}" desktop-launchers;;
  *) usage; exit 2;;
esac
