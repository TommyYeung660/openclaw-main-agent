#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Nightly Backup (local, unencrypted)
# - Snapshots workspaces + selected .openclaw config into /Users/admin/openclaw_backup
# - Commits & pushes changes for all git workspaces
# - Writes manifests under backup dest

TZ="Asia/Hong_Kong"
export TZ

BACKUP_ROOT="/Users/admin/openclaw_backup"
OPENCLAW_ROOT="/Users/admin/.openclaw"
WORKSPACE_ROOT="$OPENCLAW_ROOT/workspace"

DATE="$(date +%F)"
DEST="$BACKUP_ROOT/nightly/$DATE"

WORKSPACES_DEST="$DEST/workspaces"
OPENCLAW_DEST="$DEST/openclaw-dot/.openclaw"
MANIFESTS_DEST="$DEST/manifests"

mkdir -p "$WORKSPACES_DEST" "$OPENCLAW_DEST" "$MANIFESTS_DEST"
chmod 700 "$BACKUP_ROOT" || true

ERRORS_FILE="$MANIFESTS_DEST/errors.txt"
GIT_STATUS_FILE="$MANIFESTS_DEST/git-status.txt"
MANIFEST_JSON="$MANIFESTS_DEST/backup-manifest.json"

: > "$ERRORS_FILE"
: > "$GIT_STATUS_FILE"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" | tee -a "$ERRORS_FILE" >&2; }

RSYNC_EXCLUDES=(
  "--exclude=.venv/" "--exclude=venv/" "--exclude=node_modules/" "--exclude=dist/" "--exclude=build/" "--exclude=__pycache__/"
)

log "Backup start: $DATE"

# 1) Snapshot all workspaces
if [[ -d "$WORKSPACE_ROOT" ]]; then
  for d in "$WORKSPACE_ROOT"/*; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    log "Rsync workspace: $name"
    if ! rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$d/" "$WORKSPACES_DEST/$name/"; then
      err "rsync workspace failed: $name"
    fi
  done
else
  err "workspace root not found: $WORKSPACE_ROOT"
fi

# 2) Snapshot selected OpenClaw config (.openclaw), excluding media
log "Rsync .openclaw config (excluding media/)"
if ! rsync -a --delete \
  --exclude=media/ \
  --exclude=cache/ \
  --exclude=tmp/ \
  "$OPENCLAW_ROOT/" "$OPENCLAW_DEST/"; then
  err "rsync .openclaw failed"
fi

# 3) Update latest symlink
ln -sfn "$DEST" "$BACKUP_ROOT/latest" || true

# 4) Git commit + push for each workspace repo
log "Git push phase"
if [[ -d "$WORKSPACE_ROOT" ]]; then
  for d in "$WORKSPACE_ROOT"/*; do
    [[ -d "$d/.git" ]] || continue
    name="$(basename "$d")"

    {
      echo "--- $name"
      (cd "$d" && git status --porcelain)
      echo
    } >> "$GIT_STATUS_FILE" || true

    if (cd "$d" && git diff --quiet && git diff --cached --quiet); then
      # clean
      continue
    fi

    log "Commit+push: $name"
    if ! (cd "$d" && git add -A && git commit -m "chore(backup): nightly snapshot $DATE" >/dev/null 2>&1); then
      # If no changes to commit, ignore
      if ! (cd "$d" && git diff --quiet && git diff --cached --quiet); then
        err "git commit failed: $name"
      fi
    fi

    if ! (cd "$d" && git push); then
      err "git push failed: $name"
    fi
  done
fi

# 5) Write manifest JSON
python3 - <<PY
import json, os, time
manifest = {
  "date": "${DATE}",
  "ts": int(time.time()),
  "backupRoot": "${BACKUP_ROOT}",
  "dest": "${DEST}",
  "workspacesSrc": "${WORKSPACE_ROOT}",
  "openclawSrc": "${OPENCLAW_ROOT}",
  "notes": {
    "openclawMediaBackedUp": False,
    "encryption": "none",
  }
}
with open("${MANIFEST_JSON}", "w", encoding="utf-8") as f:
  json.dump(manifest, f, ensure_ascii=False, indent=2)
PY

log "Backup done: $DEST"

# Print a short summary to stdout (for cron message)
if [[ -s "$ERRORS_FILE" ]]; then
  echo "Backup completed with errors. See: $ERRORS_FILE"
  tail -n 20 "$ERRORS_FILE"
else
  echo "Backup completed OK. Dest: $DEST"
fi
