#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

log() { printf '[dotfiles] %s\n' "$*"; }
die() { printf '[dotfiles] ERROR: %s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
