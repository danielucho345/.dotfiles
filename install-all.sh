#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
usage() { cat <<EOF
Usage: $0 [--dry-run] [--list] <operation>
Operations: packages, dotfiles, hyprland, activitywatch, desktop-launchers, postgresql, all
EOF
}
run() { if $DRY_RUN; then echo "+ $*"; else "$@"; fi; }
run_script() { if $DRY_RUN; then "$1" --dry-run; else "$1"; fi; }
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=true; shift; }
[[ "${1:-}" == "--list" ]] && { usage; exit 0; }
op="${1:-}"; [[ -n "$op" ]] || { usage; exit 2; }
case "$op" in
  packages)
    pacman_packages=()
    aur_packages=()
    while IFS=: read -r source package; do
      [[ -z "$source" || "$source" == \#* ]] && continue
      case "$source" in
        pacman) pacman_packages+=("$package");;
        aur) aur_packages+=("$package");;
        *) echo "Unknown package source: $source" >&2; exit 1;;
      esac
    done < "$ROOT/install/packages.conf"
    if ((${#pacman_packages[@]})); then
      command -v pacman >/dev/null || { echo "pacman is required" >&2; exit 1; }
      run sudo pacman -S --needed "${pacman_packages[@]}"
    fi
    if ((${#aur_packages[@]})); then
      command -v yay >/dev/null || { echo "yay is required" >&2; exit 1; }
      run yay -S --needed "${aur_packages[@]}"
    fi;;
  dotfiles) run_script "$ROOT/install-dotfiles.sh";;
  hyprland) run_script "$ROOT/install-hyprland-overrides.sh";;
  activitywatch) run_script "$ROOT/install/install-activitywatcher.sh";;
  desktop-launchers) run_script "$ROOT/desktop-generator.sh";;
  postgresql) run_script "$ROOT/install/install-postgresql.sh";;
  all) if $DRY_RUN; then "$0" --dry-run packages; "$0" --dry-run dotfiles; "$0" --dry-run desktop-launchers; else "$0" packages; "$0" dotfiles; "$0" desktop-launchers; fi;;
  *) usage; exit 2;;
esac
