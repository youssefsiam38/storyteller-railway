#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Local smoke test. Run `docker compose build` first (CI does), or set STORYTELLER_RAILWAY_IMAGE.
# RUN_ALIGNMENT=1 additionally waits (bounded) for the test book to finish transcription+alignment.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_SECRET='local-test-only-secret-key-not-for-production-use'
LOCAL_ADMIN_PASSWORD='local-test-only-admin-password'
umask 077; printf '%s' "$LOCAL_ADMIN_PASSWORD" > "$TEST_TMP/pw"

section "fresh stack (empty volume)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/api/health" 200 420 && pass "healthy" || { compose logs --no-color storyteller | tail -40; die "never healthy"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "first-boot bootstrap"
logs=$(compose logs --no-color storyteller)
assert_contains "loopback phase" "first boot: starting Storyteller on loopback only" "$logs"
assert_contains "admin created" "admin bootstrap complete" "$logs"
assert_contains "webUrl seeded" "setting webUrl: seeded" "$logs"
assert_contains "public start" "starting Storyteller on 0.0.0.0:8001" "$logs"
assert_not_contains "secret key not in logs" "$LOCAL_SECRET" "$logs"
assert_not_contains "admin password not in logs" "$LOCAL_ADMIN_PASSWORD" "$logs"

section "process identity and listeners"
assert_eq "PID 1 user" "storyteller" "$(compose exec -T storyteller stat -c %U /proc/1 | tr -d '\r')"
assert_contains "PID 1 is tini" "tini" "$(compose exec -T storyteller sh -c 'tr "\0" " " </proc/1/cmdline' | tr -d '\r')"
tcp=$(compose exec -T storyteller sh -c 'cat /proc/net/tcp /proc/net/tcp6' | awk 'NR>1 && $4=="0A"{print $2}' | sort -u | tr '\n' ' ')
assert_contains "8001 on all interfaces" "00000000:1F41" "$tcp"
assert_contains "readium on loopback only" "0100007F:2328" "$tcp"
assert_not_contains "readium not public" "00000000:2328" "$tcp"

section "routes"
assert_eq "GET / redirects" "307" "$(http_code "$BASE_URL/")"
assert_contains "redirect target is login" "/login" "$(curl -s -o /dev/null -w '%{redirect_url}' "$BASE_URL/")"
assert_eq "GET /init is not a setup page" "307" "$(http_code "$BASE_URL/init")"
assert_not_contains "no admin creation offered" "Create admin" "$(curl -s -L "$BASE_URL/init")"
assert_eq "login page" "200" "$(http_code "$BASE_URL/login")"
assert_contains "login page is Storyteller" "Storyteller" "$(curl -s "$BASE_URL/login")"
assert_contains "health body" '"healthy"' "$(curl -s "$BASE_URL/api/health")"

section "authentication"
assert_eq "wrong password" "401" "$(http_code -X POST "$BASE_URL/api/token" -d 'username=admin&password=wrong')"
assert_eq "unauthenticated API" "401" "$(http_code "$BASE_URL/api/v2/user")"
TOK=$(login admin "$TEST_TMP/pw"); [ -n "$TOK" ] && pass "admin login" || die "admin login failed"
me=$(api "$TOK" "$BASE_URL/api/v2/user")
assert_eq "username" "admin" "$(printf '%s' "$me" | jq -r .username)"
assert_eq "email" "admin@example.invalid" "$(printf '%s' "$me" | jq -r .email)"
assert_eq "all 17 permissions" "17" "$(printf '%s' "$me" | jq '[.permissions // .permission | to_entries[] | select(.value==true)] | length')"
settings=$(api "$TOK" "$BASE_URL/api/v2/settings")
assert_contains "libraryName seeded" "Test Library" "$settings"
assert_contains "webUrl seeded" "http://localhost:8001" "$settings"

section "upload a public-domain test book (EPUB + MP3, tus)"
BOOK=$(upload_test_book "$TOK") && pass "uploaded batch ($BOOK)" || die "upload failed"
wait_book "$TOK" "$BOOK" 180 && pass "book imported with ebook and audiobook" || { book "$TOK" "$BOOK" | head -c 600; die "book not imported"; }
assert_eq "title parsed from EPUB" "Gettysburg Address" "$(book "$TOK" "$BOOK" | jq -r .title)"
st=$(proc_status "$TOK" "$BOOK")
if [ -z "$st" ]; then assert_eq "start processing" "204" "$(http_code -X POST -H "Authorization: Bearer $TOK" "$BASE_URL/api/v2/books/$BOOK/process")"; fi
for _ in $(seq 1 20); do st=$(proc_status "$TOK" "$BOOK"); [ -n "$st" ] && break; sleep 3; done
[ -n "$st" ] && pass "processing job exists ($st)" || fail "no processing status"
started=0; for _ in $(seq 1 40); do
  if logs_match "Transcribing audio file"; then started=1; break; fi; sleep 3
done
[ "$started" = 1 ] && pass "transcription started (whisper.cpp invoked)" || fail "no transcription activity in logs"
if [ "${RUN_ALIGNMENT:-0}" = 1 ]; then
  t1=$(date +%s); done_=0
  for _ in $(seq 1 180); do
    st=$(proc_status "$TOK" "$BOOK"); case "$st" in ALIGNED*) done_=1; break;; ERROR*|FAILED*) break;; esac; sleep 5
  done
  [ "$done_" = 1 ] && pass "alignment completed in $(( $(date +%s)-t1 ))s ($st)" || fail "alignment did not complete ($st)"
  echo "alignment_seconds=$(( $(date +%s)-t1 ))" >> "$METRICS"
  assert_not_contains "chapter matched transcript" "Could not find chapter" "$(compose logs --no-color storyteller)"
  assert_eq "aligned readaloud served" "200" "$(http_code -H "Authorization: Bearer $TOK" "$BASE_URL/api/v2/books/$BOOK/files")"
  assert_contains "aligned EPUB on the volume" "aligned/Gettysburg Address.epub" "$(compose exec -T storyteller sh -c 'find /data/assets -type f' | tr -d '\r')"
fi

section "graceful shutdown (SIGTERM)"
t2=$(date +%s); compose stop -t 30 storyteller; dur=$(( $(date +%s)-t2 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q storyteller)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start storyteller; wait_for_code "$BASE_URL/api/health" 200 180 && pass "restarted" || die "did not restart"
assert_contains "bootstrap skipped on restart" "existing database with users found; admin bootstrap skipped" "$(compose logs --no-color storyteller | tail -40)"

section "essential child death ends the container"
cid=$(compose ps -q storyteller); before=$(docker inspect --format '{{.RestartCount}}' "$cid")
# shellcheck disable=SC2016  # runs inside the container
compose exec -T storyteller sh -c 'for p in /proc/[0-9]*; do grep -q "next-server" "$p/cmdline" 2>/dev/null && kill -KILL "${p#/proc/}"; done' || true
for _ in $(seq 1 40); do after=$(docker inspect --format '{{.RestartCount}}' "$cid"); [ "$after" -gt "$before" ] && break; sleep 2; done
[ "${after:-0}" -gt "$before" ] && pass "container exited and restarted (restarts $before -> $after)" || fail "container did not exit after child died"
wait_for_code "$BASE_URL/api/health" 200 240 && pass "healthy again" || die "not healthy after child-death restart"

section "fail-fast validation"
img=$(compose config --images | head -1)
run_img() { docker run --rm "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img -e STORYTELLER_ADMIN_USERNAME=a -e STORYTELLER_ADMIN_PASSWORD=x -e STORYTELLER_ADMIN_EMAIL=a@b.c; then fail "should fail without secret"; else pass "exits without STORYTELLER_SECRET_KEY"; fi
assert_contains "clear secret message" "STORYTELLER_SECRET_KEY" "$(cat "$TEST_TMP/ff.log")"
if run_img -e STORYTELLER_SECRET_KEY="$LOCAL_SECRET"; then fail "should fail without admin vars"; else pass "exits without admin variables"; fi
assert_contains "clear admin message" "no administrator configured" "$(cat "$TEST_TMP/ff.log")"
if run_img -e STORYTELLER_SECRET_KEY="$LOCAL_SECRET" -e STORYTELLER_ADMIN_USERNAME=a -e STORYTELLER_ADMIN_PASSWORD=short -e STORYTELLER_ADMIN_EMAIL=a@b.c -e APP_READY_TIMEOUT=120; then fail "should fail on short password"; else pass "exits on short admin password"; fi
assert_contains "clear password message" "at least 12 characters" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "secret not echoed" "$LOCAL_SECRET" "$(cat "$TEST_TMP/ff.log")"

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version org.opencontainers.image.licenses io.storyteller-railway.upstream.version; do assert_contains "label $l" "\"$l\"" "$labels"; done
assert_eq "upstream license shipped" "MIT License" "$(compose exec -T storyteller head -1 /usr/share/licenses/storyteller-railway/STORYTELLER-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep storyteller-railway-test | sed 's/^/mem_/'
  echo "data_dir_after_tests=$(compose exec -T storyteller du -sh /data | cut -f1 | tr -d '\r')"; } | tee -a "$METRICS"
summary
