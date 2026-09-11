#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: admin, settings and an uploaded book survive container recreation; bootstrap is skipped.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077; printf '%s' 'local-test-only-admin-password' > "$TEST_TMP/pw"

section "fresh stack (first boot with a host-less STORYTELLER_WEB_URL, as when a domain does not exist yet)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
STORYTELLER_WEB_URL="https://" compose up -d --no-build; wait_for_code "$BASE_URL/api/health" 200 420 || die "not ready"
assert_contains "host-less webUrl not seeded" "setting webUrl: skipped (value has no host yet)" "$(compose logs --no-color storyteller)"

section "write state"
TOK=$(login admin "$TEST_TMP/pw"); [ -n "$TOK" ] || die "login failed"
BOOK=$(upload_test_book "$TOK") || die "upload failed"
wait_book "$TOK" "$BOOK" 180 || die "book not imported"
title=$(book "$TOK" "$BOOK" | jq -r .title)
files_before=$(compose exec -T storyteller sh -c 'find /data/assets /data/uploads -type f 2>/dev/null | wc -l' | tr -d '\r')
pass "state written: book $BOOK ($title), $files_before files under /data"

section "recreate container on the same volume (now with a real STORYTELLER_WEB_URL)"
compose down >/dev/null; compose up -d --no-build
wait_for_code "$BASE_URL/api/health" 200 420 || die "not ready after recreate"
logs=$(compose logs --no-color storyteller)
assert_contains "bootstrap skipped" "existing database with users found; admin bootstrap skipped" "$logs"
assert_not_contains "no loopback phase" "first boot: starting Storyteller on loopback" "$logs"
assert_contains "webUrl healed on second boot" "setting webUrl: seeded" "$logs"

section "verify"
TOK2=$(login admin "$TEST_TMP/pw"); [ -n "$TOK2" ] && pass "admin login still works" || die "login failed after recreate"
assert_eq "book still present" "$title" "$(book "$TOK2" "$BOOK" | jq -r .title)"
assert_contains "book listed" "$BOOK" "$(books "$TOK2")"
files_after=$(compose exec -T storyteller sh -c 'find /data/assets /data/uploads -type f 2>/dev/null | wc -l' | tr -d '\r')
[ "$files_after" -ge "$files_before" ] && pass "library files retained ($files_after)" || fail "files lost ($files_before -> $files_after)"
assert_contains "settings retained" "Test Library" "$(api "$TOK2" "$BASE_URL/api/v2/settings")"
assert_eq "webUrl now set" "http://localhost:8001" "$(api "$TOK2" "$BASE_URL/api/v2/settings" | jq -r .webUrl)"

section "a later boot with a different STORYTELLER_WEB_URL must not overwrite the stored value"
compose down >/dev/null; STORYTELLER_WEB_URL="http://changed.example.invalid:8001" compose up -d --no-build
wait_for_code "$BASE_URL/api/health" 200 420 || die "not ready after third boot"
assert_contains "left unchanged" "setting webUrl: already set, left unchanged" "$(compose logs --no-color storyteller)"
TOK3=$(login admin "$TEST_TMP/pw"); assert_eq "webUrl unchanged" "http://localhost:8001" "$(api "$TOK3" "$BASE_URL/api/v2/settings" | jq -r .webUrl)"
summary
