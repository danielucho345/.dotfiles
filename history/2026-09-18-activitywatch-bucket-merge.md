# 2026-09-18 — ActivityWatch window buckets merged

Data-changing operation. This one rewrote tracking history in `aw-server`, so it
is recorded here rather than only in the commit log.

Related commits: `664c6e1` (the cause), `9af2db5` (the fix).

## Symptom

The ActivityWatch web UI disagreed with itself. For 2026-09-18 the Activity view
reported **1h 31m 4s** and its barchart stopped just after noon, while the
Timeline view on the same day showed window events running until 19:00.

## Cause

Commit `664c6e1` replaced the legacy Python `aw-watcher-window-hyprland` with the
native Rust `awatcher`. `install/install-activitywatcher.sh` retired the old
units, their `*.wants` links and the old binary — but nothing removed the
**buckets** those watchers had already created in `aw-server`. Collection stopped;
the data rows stayed.

That left two buckets of type `currentwindow`:

| Bucket | Written by | History held |
|---|---|---|
| `aw-watcher-window-hyprland_omarchy` | legacy watcher, dead since 09-18 11:37 | 4h 48m 52s |
| `aw-watcher-window_omarchy` | `awatcher`, live | 9h 14m 59s |

aw-webui's Activity view queries exactly one window bucket —
`bid_window: buckets.window[0]` — taking the first `currentwindow` bucket the
server returns. That was the dead one. The Timeline view was unaffected because it
renders every bucket, which is precisely why the two views disagreed.

The 1h 31m 4s in the UI matched the stale bucket's day total to the second. That
was the confirming measurement.

`readme.md` had documented the leftover buckets as deliberate ("remain available
as history but receive no new events"). That assumption was the bug.

## Why merging was safe

The two buckets were near-perfect handoffs, not duplicates:

```
LEGACY  09-17 18:02 → 21:20   (3h18m)
LIVE    09-17 21:21 → 00:05   (2h44m)
LIVE    09-18 08:39 → 10:13   (1h34m)
LEGACY  09-18 10:06 → 11:37   (1h31m)   ← the only double-covered stretch
LIVE    09-18 11:37 → 18:59   (5h31m)
```

Total overlap: **6 minutes 49 seconds**, accepted rather than trimmed. Merging
recovered 4h 42m of otherwise unreachable history.

App naming matched across both watchers — both use the Wayland `app_id`
convention. 15 names were shared verbatim (`chromium`, `chatgpt`, `Alacritty`,
`org.mozilla.Thunderbird`, `steam`, …), so category rules applied unchanged to the
merged history. The 6 legacy-only names were just apps that never ran during an
`awatcher` window.

## What changed

- **`install/migrate-activitywatch-buckets.sh`** — new, idempotent. Archives every
  bucket, copies the legacy window events into `aw-watcher-window_<hostname>`
  (stripping server-assigned ids, bulk `POST /events` rather than `/heartbeat`),
  verifies the event count moved before deleting anything, then drops both
  `*-hyprland_<hostname>` buckets and asserts one `currentwindow` bucket remains.
- **`install/install-activitywatcher.sh`** — runs the migration after enabling the
  units, so a re-run or a fresh machine heals itself instead of recreating the
  split.
- **`readme.md`** — the "remain available as history" paragraph replaced.

The workspace bucket was archived but never merged: `awatcher` emits no workspace
events, so there was no target. **Hyprland workspace tracking is gone as a live
signal** — that was a deliberate call, not an oversight.

## Verification before it touched real data

The destructive path was rehearsed against a throwaway server rather than
dry-run only:

```bash
aw-server-rust --testing --port 5699 --dbpath <scratch>/test.db --no-legacy-import
```

seeded with an exact copy of all three real buckets, then migrated. Results:
merged bucket held **2390 = 1225 + 1165** events exactly; 09-17 totals matched to
the second (`3:17:48 + 2:35:37 = 5:53:25`); a second run exited cleanly with
"nothing to migrate". A 10s discrepancy on 09-18 turned out to be `awatcher`
extending the in-progress event's duration mid-test, same event — not a defect.

This is what `AW_SERVER_URL` in the migration script exists for.

## Result

Applied 2026-09-18 19:11. 1225 events merged; both `*-hyprland_*` buckets deleted.

| | Before | After |
|---|---|---|
| `currentwindow` buckets | 2 | 1 |
| Activity view, 2026-09-18 | 1h 31m 4s | 8h 1m 3s |
| Raw event total, 2026-09-18 | 6h 38m 51s | 8h 33m 44s |
| Raw event total, 2026-09-17 | 2h 35m 37s | 5h 53m 25s |

Spotify, the Steam titles, Plane and `com.anthropic.Claude` appear in Top
Applications for the first time — all were invisible while the view read the dead
bucket.

## Tracing it back / rollback

- `~/sqlite.db.bak` — byte-for-byte snapshot of the database taken immediately
  before the merge. Restore by stopping `aw-server-rust.service`, copying it over
  `~/.local/share/activitywatch/aw-server-rust/sqlite.db`, and starting again.
- `~/.local/state/dotfiles-backups/20260918-191138/activitywatch/` — JSON exports
  written by the migration itself: a full server export plus per-bucket exports of
  both deleted buckets. **This is the only remaining copy of the Hyprland
  workspace history.**

Neither is in version control. Delete `~/sqlite.db.bak` once the merged data has
been trusted for a while; keep the JSON archive longer if the workspace history
might ever be wanted.

## Still open

`awatcher` reports **1h 42m 54s** of windows as `app: "unknown"` across the merged
bucket — third by duration behind `chromium` and `chatgpt`. The legacy watcher
never emitted `unknown`, so this is a separate regression from the same commit
`664c6e1`. Not investigated here. Note that `steam_app_1151640` and
`steam_app_553850` *do* resolve, which argues against a simple "XWayland is
broken" explanation.
