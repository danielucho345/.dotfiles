#!/usr/bin/env bash
set -Eeuo pipefail

# Completes the migration from the legacy aw-watcher-window-hyprland collectors
# to the native awatcher. The units and binary are retired by
# install-activitywatcher.sh, but the buckets those watchers created stay behind
# in aw-server. Two buckets of type currentwindow then coexist, and the web UI
# graphs read only the first one they are given, which is the dead one. This
# folds the legacy window history into the live bucket and removes the leftovers.

API="${AW_SERVER_URL:-http://127.0.0.1:5600}/api/0"
BACKUP_ROOT="$HOME/.local/state/dotfiles-backups"
CHUNK_SIZE=200
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ -z "${1:-}" || "$DRY_RUN" == true ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 2; }

require_command() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }

require_command curl
require_command python3

http_status() { curl --silent --output /dev/null --write-out '%{http_code}' "$@"; }
bucket_exists() { [[ "$(http_status "$API/buckets/$1")" == "200" ]]; }

event_count() {
  curl --fail --silent "$API/buckets/$1/events?limit=-1" |
    python3 -c 'import json, sys; print(len(json.load(sys.stdin)))'
}

# Same readiness check the aw-awatcher unit runs before starting the watcher.
wait_for_server() {
  local attempt
  for ((attempt = 0; attempt < 120; attempt++)); do
    if curl --fail --silent --max-time 1 "$API/info" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "aw-server is not responding at $API" >&2
  exit 1
}

wait_for_server

HOST="$(curl --fail --silent "$API/info" |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["hostname"])')"
[[ -n "$HOST" ]] || { echo "Could not determine the ActivityWatch hostname" >&2; exit 1; }

LEGACY_WINDOW="aw-watcher-window-hyprland_$HOST"
LEGACY_WORKSPACE="aw-watcher-workspace-hyprland_$HOST"
TARGET="aw-watcher-window_$HOST"

legacy_buckets=()
if bucket_exists "$LEGACY_WINDOW"; then legacy_buckets+=("$LEGACY_WINDOW"); fi
if bucket_exists "$LEGACY_WORKSPACE"; then legacy_buckets+=("$LEGACY_WORKSPACE"); fi

if ((${#legacy_buckets[@]} == 0)); then
  echo "No legacy ActivityWatch buckets on $HOST; nothing to migrate."
  exit 0
fi

# Merging into a bucket that does not exist would silently create an empty one
# and then delete the only copy of the history.
bucket_exists "$TARGET" || {
  echo "Cannot migrate: $TARGET does not exist, so awatcher has never run." >&2
  echo "Start aw-awatcher.service and retry." >&2
  exit 1
}

if $DRY_RUN; then
  echo "+ back up $API/export and ${legacy_buckets[*]} to $BACKUP_ROOT/<timestamp>/activitywatch"
  if bucket_exists "$LEGACY_WINDOW"; then
    echo "+ copy $(event_count "$LEGACY_WINDOW") events from $LEGACY_WINDOW into $TARGET"
  fi
  for bucket in "${legacy_buckets[@]}"; do
    echo "+ curl --request DELETE $API/buckets/$bucket"
  done
  exit 0
fi

BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)/activitywatch"
mkdir -p "$BACKUP_DIR"
curl --fail --silent "$API/export" --output "$BACKUP_DIR/aw-full-export.json"
for bucket in "${legacy_buckets[@]}"; do
  curl --fail --silent "$API/buckets/$bucket/export" --output "$BACKUP_DIR/$bucket.json"
done
echo "Archived ActivityWatch data to $BACKUP_DIR"

# The workspace bucket is archived and dropped but never merged: awatcher emits
# no workspace events, so there is no live bucket to merge it into.
if bucket_exists "$LEGACY_WINDOW"; then
  before="$(event_count "$TARGET")"
  merged="$(python3 - "$API" "$LEGACY_WINDOW" "$TARGET" "$CHUNK_SIZE" <<'PY'
import json
import sys
import urllib.request

api, source, target, chunk = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

with urllib.request.urlopen(f"{api}/buckets/{source}/events?limit=-1") as response:
    events = json.load(response)

# Server-assigned ids belong to the source bucket and would collide in the target.
for event in events:
    event.pop("id", None)

# Bulk create, not heartbeat: these events are not contiguous with the target's
# and heartbeat merging would distort their durations.
for start in range(0, len(events), chunk):
    request = urllib.request.Request(
        f"{api}/buckets/{target}/events",
        data=json.dumps(events[start:start + chunk]).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request):
        pass

print(len(events))
PY
  )"
  after="$(event_count "$TARGET")"
  if ((after - before != merged)); then
    echo "Migration aborted: expected $merged new events in $TARGET, found $((after - before))." >&2
    echo "The legacy buckets have been left intact. Restore from $BACKUP_DIR if needed." >&2
    exit 1
  fi
  echo "Merged $merged events from $LEGACY_WINDOW into $TARGET"
fi

delete_bucket() {
  local bucket="$1" status
  status="$(http_status --request DELETE "$API/buckets/$bucket")"
  # aw-server-rust deletes outright; the Python server requires the force flag.
  if [[ $status != 2* ]]; then
    status="$(http_status --request DELETE "$API/buckets/$bucket?force=1")"
  fi
  [[ $status == 2* ]] || { echo "Failed to delete $bucket (HTTP $status)" >&2; exit 1; }
  echo "Deleted $bucket"
}

for bucket in "${legacy_buckets[@]}"; do
  delete_bucket "$bucket"
done

remaining="$(curl --fail --silent "$API/buckets/" | python3 -c '
import json
import sys

buckets = json.load(sys.stdin)
print("\n".join(k for k, v in buckets.items() if v.get("type") == "currentwindow"))
')"
if [[ "$remaining" != "$TARGET" ]]; then
  echo "Expected $TARGET to be the only currentwindow bucket, found:" >&2
  echo "$remaining" >&2
  exit 1
fi

echo "ActivityWatch buckets migrated; $TARGET is the only window bucket."
