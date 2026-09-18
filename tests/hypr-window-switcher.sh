#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWITCHER_UNDER_TEST="${SWITCHER_UNDER_TEST:-$ROOT/bin/hypr-window-switcher}"
SWITCHER_TEST_LOG="$(mktemp)"
export SWITCHER_TEST_LOG
trap 'rm -f -- "$SWITCHER_TEST_LOG"' EXIT

hyprctl() {
  case "$*" in
    '-j clients')
      printf '%s\n' '[
        {"address":"0xb","class":"Discord","title":"Team\nChat\t日本語 C:\\notes","workspace":{"id":5,"name":"5"}},
        {"address":"0xa","class":"","title":"","workspace":{"id":1,"name":"1"}},
        {"address":"0xc","class":"Hidden","title":"Scratchpad","workspace":{"id":-99,"name":"special:scratchpad"}}
      ]'
      ;;
    '-j workspaces')
      printf '%s\n' '[{"id":1,"monitor":"DP-1"},{"id":5,"monitor":"DP-2"}]'
      ;;
    '-j monitors') printf '%s\n' '[{"name":"DP-1","x":0,"y":0},{"name":"DP-2","x":1920,"y":0}]' ;;
    '-j activewindow') printf '%s\n' '{"address":"0xb"}' ;;
    dispatch*) printf '%s\n' "$*" >> "$SWITCHER_TEST_LOG"; printf '%s\n' ok ;;
    *) return 1 ;;
  esac
}

omarchy() {
  [[ "$1 $2" == 'menu select' ]] || return 1
  shift 3
  [[ "$3" == -- ]] || { echo 'Expected exactly two regular windows' >&2; exit 1; }
  [[ "$1" == *'1. Unknown application — Untitled window'* ]] || exit 1
  [[ "$2" == *'2. Discord — Team Chat 日本語 C:\notes'* ]] || exit 1
  [[ "$2" == *'Workspace 5 · DP-2'* ]] || exit 1
  [[ "${SWITCHER_CANCEL:-false}" == false ]] || return 1

  # Match Menu.qml: split on real tabs, remove the icon, return label + detail.
  # Derive the result from the actual row instead of inventing a valid result.
  local row="$2"
  [[ "$row" == *$'\t'* ]] && row="${row#*$'\t'}"
  printf '%s\n' "$row"
}

export -f hyprctl omarchy
bash "$SWITCHER_UNDER_TEST" legacy
expected=$'dispatch hl.dsp.focus({ monitor = "DP-2" })\ndispatch hl.dsp.focus({ workspace = "5" })\ndispatch hl.dsp.focus({ window = "address:0xb" })'
[[ "$(<"$SWITCHER_TEST_LOG")" == "$expected" ]]
printf '%s\n' 'PASS: real menu row parsing reaches the selected window'

: > "$SWITCHER_TEST_LOG"
SWITCHER_CANCEL=true bash "$SWITCHER_UNDER_TEST" legacy
[[ ! -s "$SWITCHER_TEST_LOG" ]]
printf '%s\n' 'PASS: cancellation does not dispatch a focus command'
