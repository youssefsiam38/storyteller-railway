#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for storyteller-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://localhost:8001}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }
# logs_match PATTERN -> true if the storyteller container logs match (extended regex, case-insensitive)
logs_match() { local l; l=$(compose logs --no-color storyteller 2>/dev/null); grep -qiE -- "$1" <<<"$l"; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

# login USERNAME PASSWORD_FILE -> prints bearer token (password read from file, never from argv)
login() {
  curl -s -X POST "$BASE_URL/api/token" --data-urlencode "username=$1" --data-urlencode "password@$2" | jq -r '.access_token // empty'
}
api() { local tok=$1; shift; curl -s -H "Authorization: Bearer $tok" "$@"; }

make_epub() { python3 "$REPO_ROOT/tests/fixtures/make-epub.py" "$1" >/dev/null; }
compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

b64() { printf '%s' "$1" | base64 -w0; }
# tus_upload TOKEN FILE BOOKUUID TOTALFILES [MIME] -> uploads one file into the book's upload batch
tus_upload() {
  local tok=$1 f=$2 uuid=$3 total=$4 type=${5:-} size meta loc code
  size=$(stat -c %s "$f")
  meta="filename $(b64 "$(basename "$f")"),bookUuid $(b64 "$uuid"),totalFiles $(b64 "$total")"
  [ -n "$type" ] && meta="$meta,filetype $(b64 "$type")"
  loc=$(curl -s -D - -o /dev/null -X POST "$BASE_URL/api/v2/books/upload" -H "Authorization: Bearer $tok" \
        -H "Tus-Resumable: 1.0.0" -H "Upload-Length: $size" -H "Upload-Metadata: $meta" | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')
  [ -n "$loc" ] || { echo "tus create failed for $f" >&2; return 1; }
  case "$loc" in http*) ;; /*) loc="$BASE_URL$loc";; *) loc="$BASE_URL/api/v2/books/upload/$loc";; esac
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$loc" -H "Authorization: Bearer $tok" -H "Tus-Resumable: 1.0.0" \
         -H "Upload-Offset: 0" -H "Content-Type: application/offset+octet-stream" --data-binary "@$f" --max-time 300)
  [ "$code" = 204 ] || { echo "tus patch returned $code for $f" >&2; return 1; }
}
# books TOKEN -> JSON array of books
books() { api "$1" "$BASE_URL/api/v2/books" | jq -c 'if type=="array" then . else (.books // .items // .data // []) end'; }
# book TOKEN UUID -> JSON
book() { api "$1" "$BASE_URL/api/v2/books/$2"; }
# wait_book TOKEN UUID TIMEOUT -> waits until the book has both ebook and audiobook
wait_book() {
  local tok=$1 uuid=$2 timeout=${3:-120} start; start=$(date +%s)
  while :; do
    if book "$tok" "$uuid" | jq -e '.ebook and .audiobook and (.ebook.missing|not) and (.audiobook.missing|not)' >/dev/null 2>&1; then return 0; fi
    [ $(( $(date +%s) - start )) -ge "$timeout" ] && return 1
    sleep 3
  done
}
# upload_test_book TOKEN -> prints the new book uuid (EPUB + MP3 fixture, one batch)
upload_test_book() {
  local tok=$1 uuid epub
  uuid=$(python3 -c 'import uuid;print(uuid.uuid4())')
  epub="$TEST_TMP/gettysburg.epub"; make_epub "$epub"
  tus_upload "$tok" "$epub" "$uuid" 2 application/epub+zip || return 1
  tus_upload "$tok" "$REPO_ROOT/tests/fixtures/gettysburg_address_lincoln_64kb.mp3" "$uuid" 2 audio/mpeg || return 1
  printf '%s' "$uuid"
}
# proc_status TOKEN UUID -> "STATUS:STAGE:PROGRESS" from the book's readaloud record, or empty
proc_status() { book "$1" "$2" | jq -r '.readaloud | if . then "\(.status):\(.currentStage // "?"):\(.stageProgress // "")" else "" end'; }
