#!/bin/bash
# storyteller-railway entrypoint (runs as root; the upstream entrypoint drops to `storyteller`).
#
#   1. validate variables (names only; values are never printed)
#   2. first boot only: start Storyteller on loopback, wait for /api/health, create the
#      administrator from STORYTELLER_ADMIN_* using the app's own argon2, stop it
#   3. exec the upstream entrypoint (gosu + tini + node) bound to 0.0.0.0 for public traffic
#
# Result: the unauthenticated "create admin account" page is never reachable from the internet.
set -u

log()  { printf '[storyteller-railway] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

: "${PORT:=8001}"
: "${STORYTELLER_DATA_DIR:=/data}"
: "${APP_READY_TIMEOUT:=300}"
export PORT STORYTELLER_DATA_DIR
DB_FILE="${STORYTELLER_DB_DIR:-$STORYTELLER_DATA_DIR}/${STORYTELLER_DB_FILENAME:-storyteller.db}"
UPSTREAM_ENTRYPOINT=$(command -v entrypoint.sh) || fail "upstream entrypoint.sh not found in image"
BOOTSTRAP=/usr/local/lib/storyteller-railway/bootstrap-admin.mjs

# --- required variables -------------------------------------------------------------------------
if [ -z "${STORYTELLER_SECRET_KEY:-}" ] && [ -z "${STORYTELLER_SECRET_KEY_FILE:-}" ]; then
  fail "STORYTELLER_SECRET_KEY (or STORYTELLER_SECRET_KEY_FILE) is required"
fi
if [ -n "${STORYTELLER_SECRET_KEY:-}" ] && [ "${#STORYTELLER_SECRET_KEY}" -lt 32 ]; then
  fail "STORYTELLER_SECRET_KEY must be at least 32 characters"
fi

bootstrap_mode=0
if [ -n "${STORYTELLER_ADMIN_USERNAME:-}" ] || [ -n "${STORYTELLER_ADMIN_PASSWORD:-}" ] || [ -n "${STORYTELLER_ADMIN_EMAIL:-}" ]; then
  if [ -z "${STORYTELLER_ADMIN_USERNAME:-}" ] || [ -z "${STORYTELLER_ADMIN_PASSWORD:-}" ] || [ -z "${STORYTELLER_ADMIN_EMAIL:-}" ]; then
    fail "set all of STORYTELLER_ADMIN_USERNAME, STORYTELLER_ADMIN_PASSWORD, STORYTELLER_ADMIN_EMAIL (or none)"
  fi
  bootstrap_mode=1
elif [ "${STORYTELLER_ALLOW_OPEN_SETUP:-false}" != "true" ]; then
  fail "no administrator configured. Set STORYTELLER_ADMIN_USERNAME, STORYTELLER_ADMIN_PASSWORD and STORYTELLER_ADMIN_EMAIL so the admin is created before the service is exposed, or set STORYTELLER_ALLOW_OPEN_SETUP=true to accept an unauthenticated first-run setup page (not recommended on a public URL)."
fi

mkdir -p "$STORYTELLER_DATA_DIR" || fail "cannot create $STORYTELLER_DATA_DIR"

# --- does the database already have a user? ----------------------------------------------------
users_exist() {
  [ -f "$DB_FILE" ] || return 1
  n=$(node -e '
    const { DatabaseSync } = require("node:sqlite");
    try { const db = new DatabaseSync(process.argv[1], { readOnly: true }); db.exec("PRAGMA busy_timeout=5000");
      console.log(db.prepare("SELECT count(*) AS n FROM user").get().n); } catch (e) { console.log("0"); }
  ' "$DB_FILE" 2>/dev/null)
  [ "${n:-0}" -gt 0 ]
}

child=""
on_signal() {
  log "stop signal received during bootstrap, stopping Storyteller"
  [ -n "$child" ] && kill -TERM "$child" 2>/dev/null
  [ -n "$child" ] && wait "$child"
  exit 143
}

if [ "$bootstrap_mode" = 1 ] && ! users_exist; then
  log "first boot: starting Storyteller on loopback only to create the administrator"
  trap on_signal TERM INT
  HOSTNAME=127.0.0.1 "$UPSTREAM_ENTRYPOINT" "$@" &
  child=$!
  deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
  while :; do
    if ! kill -0 "$child" 2>/dev/null; then wait "$child"; fail "Storyteller exited during first boot with status $?"; fi
    if curl -fsS -m 5 -o /dev/null "http://127.0.0.1:${PORT}/api/health" 2>/dev/null; then break; fi
    [ "$(date +%s)" -lt "$deadline" ] || { kill -TERM "$child"; wait "$child"; fail "Storyteller did not become healthy within ${APP_READY_TIMEOUT}s during first boot"; }
    sleep 2
  done
  log "Storyteller is healthy on loopback; creating the administrator"
  if ! gosu storyteller node --no-warnings "$BOOTSTRAP"; then
    kill -TERM "$child"; wait "$child"; fail "administrator bootstrap failed"
  fi
  log "stopping loopback instance"
  kill -TERM "$child"; wait "$child" || true
  trap - TERM INT
  users_exist || fail "administrator not found after bootstrap"
elif [ "$bootstrap_mode" = 1 ]; then
  log "existing database with users found; admin bootstrap skipped"
fi

log "starting Storyteller on ${HOSTNAME:-0.0.0.0}:${PORT}"
export HOSTNAME="${HOSTNAME:-0.0.0.0}"
exec "$UPSTREAM_ENTRYPOINT" "$@"
