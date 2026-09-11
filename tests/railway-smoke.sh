#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional login + workflow: ADMIN_USERNAME=admin ADMIN_PASSWORD_FILE=/path/to/file
#   STATE_OUT=/path/state.json (upload a test book) / STATE_IN=/path/state.json (verify after redeploy)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and redirects"
assert_eq "https root redirects to login" "307" "$(http_code "$BASE_URL/")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/api/health" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 15 "http://$host/")"

section "readiness and first-run safety"
assert_eq "healthcheck route" "200" "$(http_code "$BASE_URL/api/health")"
assert_contains "health body" '"healthy"' "$(curl -s "$BASE_URL/api/health")"
assert_eq "/init is not a setup page" "307" "$(http_code "$BASE_URL/init")"
assert_not_contains "no admin creation offered" "Create admin" "$(curl -s -L "$BASE_URL/init")"
assert_eq "login page" "200" "$(http_code "$BASE_URL/login")"
assert_eq "unauthenticated API" "401" "$(http_code "$BASE_URL/api/v2/user")"
assert_eq "wrong password" "401" "$(http_code -X POST "$BASE_URL/api/token" -d 'username=nobody&password=wrong')"

if [ -n "${ADMIN_PASSWORD_FILE:-}" ]; then
  section "admin login through the public domain"
  TOK=$(login "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD_FILE"); [ -n "$TOK" ] && pass "login with generated credentials" || die "login failed"
  me=$(api "$TOK" "$BASE_URL/api/v2/user")
  assert_eq "all 17 permissions" "17" "$(printf '%s' "$me" | jq '[.permissions // .permission | to_entries[] | select(.value==true)] | length')"
  assert_contains "webUrl is the public origin" "$BASE_URL" "$(api "$TOK" "$BASE_URL/api/v2/settings" | jq -r '.webUrl // ""')"
  if [ -n "${STATE_OUT:-}" ]; then
    section "upload test book"
    BOOK=$(upload_test_book "$TOK") && pass "uploaded ($BOOK)" || die "upload failed"
    wait_book "$TOK" "$BOOK" 240 && pass "imported with ebook and audiobook" || die "not imported"
    st=$(proc_status "$TOK" "$BOOK"); [ -n "$st" ] || { api "$TOK" -X POST "$BASE_URL/api/v2/books/$BOOK/process" -o /dev/null; sleep 5; st=$(proc_status "$TOK" "$BOOK"); }
    pass "processing status: ${st:-none}"
    jq -n --arg b "$BOOK" --arg t "$(book "$TOK" "$BOOK" | jq -r .title)" '{book:$b, title:$t}' > "$STATE_OUT"; pass "state written"
  fi
  if [ -n "${STATE_IN:-}" ]; then
    section "verify state after redeploy"
    B=$(jq -r .book "$STATE_IN")
    assert_eq "book still present" "$(jq -r .title "$STATE_IN")" "$(book "$TOK" "$B" | jq -r .title)"
    st=$(proc_status "$TOK" "$B"); pass "processing status after redeploy: ${st:-none}"
    if [ "${WAIT_ALIGNMENT:-0}" = 1 ]; then
      done_=0; for _ in $(seq 1 240); do st=$(proc_status "$TOK" "$B"); case "$st" in ALIGNED*) done_=1; break;; ERROR*|FAILED*) break;; esac; sleep 5; done
      [ "$done_" = 1 ] && pass "alignment completed on Railway ($st)" || fail "alignment not completed ($st)"
    fi
  fi
fi
summary
