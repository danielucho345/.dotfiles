#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/install/plugins.json"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
PLUGIN_ROOT="$CONFIG_ROOT/plugins"
CACHE_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/omarchy-plugins"
DRY_RUN=false
FORCE=false
CHECK_ONLY=false
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --check) CHECK_ONLY=true; DRY_RUN=true; shift ;;
    *) echo "Usage: $0 [--dry-run] [--force]" >&2; exit 2 ;;
  esac
done
fail() { echo "Plugins: $*" >&2; exit 1; }
report() { if ! $CHECK_ONLY; then printf '%s\n' "$*"; fi; }
for command in jq git omarchy omarchy-shell; do
  command -v "$command" >/dev/null || fail "$command is required"
done

jq -e '
  .version == 1 and (.plugins | type == "array" and length > 0)
  and ([.plugins[].id] | length == (unique | length))
  and all(.plugins[];
    (.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")
      and (contains("..") | not) and (startswith("omarchy.") | not))
    and (.enabled | type == "boolean")
    and (if has("path") then
      (.path | type == "string" and length > 0 and (startswith("/") | not)
        and (split("/") | all(. != "..")))
      and (has("url") | not) and (has("revision") | not)
    else
      (.url | type == "string" and length > 0 and (startswith("-") | not))
      and (.revision | type == "string" and test("^[0-9a-f]{40}$"))
    end))
' "$MANIFEST" >/dev/null || fail "invalid manifest: $MANIFEST"

# Adding an entry through a linked shared directory could modify the checkout
# itself. Refuse before creating caches, links, or backups.
for parent in "${XDG_CONFIG_HOME:-$HOME/.config}" "$CONFIG_ROOT" "$PLUGIN_ROOT"; do
  [[ ! -L "$parent" ]] || fail "shared directory is symlinked: $parent; replace it with a real directory, retaining its contents, before installing plugins"
  [[ ! -e "$parent" || -d "$parent" ]] || fail "not a directory: $parent"
done
if [[ -e "$CONFIG_ROOT/shell.json" || -L "$CONFIG_ROOT/shell.json" ]]; then
  jq -e 'type == "object" and .version == 1' "$CONFIG_ROOT/shell.json" >/dev/null \
    || fail "invalid shell config: $CONFIG_ROOT/shell.json; repair it before installing plugins"
fi

validate_plugin() {
  local directory="$1" id="$2"
  directory="$(realpath -e "$directory")" || fail "missing plugin source: $directory"
  jq -e --arg id "$id" '.id == $id' "$directory/manifest.json" >/dev/null \
    || fail "manifest ID does not match $id in $directory"
  omarchy plugin validate "$directory" || fail "invalid plugin: $directory"
}
matching_checkout() {
  local directory="$1" url="$2" revision="$3" top status
  [[ -d "$directory" ]] || return 1
  top="$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$(realpath "$directory")" == "$(realpath "$top")" ]] || return 1
  [[ "$(git -C "$directory" remote get-url origin 2>/dev/null)" == "$url" ]] || return 1
  [[ "$(git -C "$directory" rev-parse HEAD)" == "$revision" ]] || return 1
  status="$(git --no-optional-locks -C "$directory" status --porcelain --untracked-files=all)" || return 1
  [[ -z "$status" ]]
}

ids=() sources=() targets=() urls=() revisions=() enabled_states=() replacements=()
while IFS= read -r entry; do
  id="$(jq -r '.id' <<<"$entry")"
  enabled="$(jq -r '.enabled' <<<"$entry")"
  path="$(jq -r '.path // empty' <<<"$entry")"
  url="$(jq -r '.url // empty' <<<"$entry")"
  revision="$(jq -r '.revision // empty' <<<"$entry")"
  target="$PLUGIN_ROOT/$id"
  replace=false
  if [[ -n "$path" ]]; then
    source="$(realpath -m "$ROOT/$path")"
    [[ "$source" == "$ROOT/"* ]] || fail "source escapes repository: $path"
    validate_plugin "$source" "$id"
    report "$id: repository source $path; enabled=$enabled"
    matches=false
    if [[ -L "$target" && "$(readlink -f "$target")" == "$source" ]]; then matches=true; fi
  else
    source="$CACHE_ROOT/$id/$revision"
    matches=false
    # Keep a matching existing checkout, including a user's original clone.
    if matching_checkout "$target" "$url" "$revision"; then
      validate_plugin "$target" "$id"
      source="$target"
      matches=true
      report "$id: reuse $target at $revision; enabled=$enabled"
    else
      if [[ -e "$source" || -L "$source" ]]; then
        [[ ! -L "$source" ]] && matching_checkout "$source" "$url" "$revision" \
          || fail "managed checkout is modified or mismatched: $source; move it aside before retrying"
        validate_plugin "$source" "$id"
        report "$id: reuse cached revision $revision; enabled=$enabled"
      else
        report "$id: would fetch $url at $revision into $source; enabled=$enabled"
      fi
    fi
  fi
  if [[ -e "$target" || -L "$target" ]] && ! $matches; then
    $FORCE || fail "conflict: $target; use --force to back up and replace it"
    replace=true
    report "Would back up conflicting plugin $target before replacement."
  fi
  ids+=("$id"); sources+=("$source"); targets+=("$target")
  urls+=("$url"); revisions+=("$revision"); enabled_states+=("$enabled"); replacements+=("$replace")
done < <(jq -c '.plugins[]' "$MANIFEST")

if $DRY_RUN; then
  report "Would install plugin links, rescan, and apply declared states (backing up shell.json if states change)."
  report "Without Omarchy Shell, activation remains pending; finish after login with: ./install-all.sh plugins"
  exit 0
fi

staging=""
trap '[[ -z "$staging" ]] || rm -rf -- "$staging"' EXIT
# Fetch and validate every source before replacing any live plugin.
for i in "${!ids[@]}"; do
  source="${sources[i]}"
  [[ -n "${urls[i]}" && ! -e "$source" ]] || continue
  mkdir -p "$(dirname "$source")"
  staging="$(mktemp -d "$(dirname "$source")/.fetch.XXXXXXXX")"
  git init -q "$staging"
  git -C "$staging" remote add origin "${urls[i]}"
  git -C "$staging" fetch --depth=1 origin "${revisions[i]}"
  git -C "$staging" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  matching_checkout "$staging" "${urls[i]}" "${revisions[i]}" || fail "fetched checkout does not match ${ids[i]}"
  validate_plugin "$staging" "${ids[i]}"
  mv -T -- "$staging" "$source"
  staging=""
done

backup_root=""
mkdir -p "$PLUGIN_ROOT"
for i in "${!ids[@]}"; do
  source="${sources[i]}"; target="${targets[i]}"
  if [[ "$source" == "$target" || ( -L "$target" && "$(readlink -f "$target")" == "$source" ) ]]; then continue; fi
  if ${replacements[i]}; then
    if [[ -z "$backup_root" ]]; then
      backup_parent="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"
      mkdir -p "$backup_parent"
      backup_root="$(mktemp -d "$backup_parent/plugins.$(date +%Y%m%d-%H%M%S).XXXXXXXX")"
    fi
    mv -- "$target" "$backup_root/${ids[i]}"
    echo "Backed up plugin to $backup_root/${ids[i]}"
  fi
  ln -s -- "$source" "$target"
done

if ! omarchy-shell shell ping >/dev/null 2>&1; then
  echo "Plugin files installed; activation PENDING (Omarchy Shell is unavailable)."
  echo "After login run: ./install-all.sh plugins"
  exit 0
fi
omarchy-shell shell rescanPlugins
discovered=false
for _ in {1..40}; do
  if catalog="$(omarchy plugin list --json)" && jq -e --slurpfile manifest "$MANIFEST" '
    . as $catalog | all($manifest[0].plugins[]; .id as $id | any($catalog[]; .id == $id))
  ' <<<"$catalog" >/dev/null; then
    discovered=true
    break
  fi
  sleep 0.05
done
$discovered || fail "plugin discovery did not finish; retry: ./install-all.sh plugins"

changes=()
# Disable first so any cloned built-in service is restored before enabling
# the requested replacements. Commands preserve unrelated configuration.
for desired in false true; do
  for i in "${!ids[@]}"; do
    [[ "${enabled_states[i]}" == "$desired" ]] || continue
    if ! jq -e --arg id "${ids[i]}" --argjson enabled "$desired" \
      'any(.[]; .id == $id and .enabled == $enabled)' <<<"$catalog" >/dev/null; then
      changes+=("$i")
    fi
  done
done
if ((${#changes[@]})); then
  shell_config="$CONFIG_ROOT/shell.json"
  if [[ -e "$shell_config" || -L "$shell_config" ]]; then
    backup="$(mktemp -d "$shell_config.bak.$(date +%Y%m%d-%H%M%S).XXXXXXXX")"
    cp -a -- "$shell_config" "$backup/shell.json"
    [[ ! -L "$shell_config" ]] || cp -L -- "$shell_config" "$backup/shell.contents.json"
    echo "Backed up shell config to $backup"
  fi
  for i in "${changes[@]}"; do
    action=disable
    ${enabled_states[i]} && action=enable
    omarchy plugin "$action" "${ids[i]}"
  done
fi
# Read back the actual state; a successful IPC call alone is insufficient.
catalog="$(omarchy plugin list --json)"
jq -e --slurpfile manifest "$MANIFEST" '
  . as $catalog | all($manifest[0].plugins[];
    . as $wanted | any($catalog[]; .id == $wanted.id and .enabled == $wanted.enabled))
' <<<"$catalog" >/dev/null || fail "plugin states did not match the manifest; retry: ./install-all.sh plugins"
echo "Plugins installed; all declared states verified."
