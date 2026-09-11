# Upstream: Storyteller

Facts checked against primary sources on 2026-09-11. Re-verify before every upgrade.

## Identity

| Item | Value |
|---|---|
| Project | Storyteller — self-hosted platform that aligns an ebook with its audiobook and produces read-along (EPUB 3 Media Overlay) books; web library + iOS/Android apps |
| Repository | https://gitlab.com/storyteller-platform/storyteller (moved from `gitlab.com/smoores/storyteller` in March 2025; the old repo is a stale mirror) |
| Website / docs | https://storyteller-platform.dev (docs source: `applications/docs/docs/` in the repo) |
| Maintainer | Shane Friedman and contributors (`storyteller-platform` GitLab group) |
| License | MIT — `LICENSE` at repository root ("Copyright (c) 2023 Shane Friedman"). GitLab's API reports no license detection, but the file is present and unambiguous. |
| Security policy | None published. Bugs go to GitLab issues; the docs list a Discord for support. |
| Activity (snapshot) | last push 2026-09-11; ~220 GitLab stars; frequent releases per package (`web-v*`, `docs-v*`, `align-v*` tags in a monorepo) |
| Trademark / naming | "Storyteller" is the project's name. This template is a *community-maintained Railway template for Storyteller*, *not affiliated with the Storyteller project*. |

## Pinned release

| Item | Value |
|---|---|
| Web release | `web-v2.14.21`, tagged 2026-08-18 (the `v3.0.0-beta.*` tags are pre-release and not used) |
| Git commit | `fbf6d83ff289e106e1c44bf48aeb325722d160e9` |
| Image | `registry.gitlab.com/storyteller-platform/storyteller:web-v2.14.21` |
| Image index digest | `sha256:f063fcd838ffd9723d581d7a190135069c58c595e6ce9ac41b5e2f8bec090db7` (identical to `latest` on 2026-09-11) |
| Platforms | `linux/amd64` (`sha256:c684f35801416443a12f49051697d26e65341b2b003b2d58e62fdd613f3563cb`), `linux/arm64` (`sha256:e1b1bca672ca5e115e1c35bd5762ad664608b6c5039a8f21dcb9f1ed1ba44071`) |
| Image source | Built by upstream GitLab CI (`.gitlab-ci.yml`) from `Dockerfile` on `storyteller-base:main` (Ubuntu 24.04). Includes Node 24.8, ffmpeg, gosu, tini, sqlite3, Readium 0.6.5 (`ghcr.io/readium/readium:0.6.5`), whisper.cpp v1.8.2 CPU builds and the `tiny.en` model. |
| Image size | ~2.9 GB uncompressed (`linux/amd64`) |
| Checksums | Upstream publishes no separate checksum files; OCI digests above are the integrity anchor, read with `docker buildx imagetools inspect`. |
| GPU variants | `amd64-cuda-*`, `amd64-rocm`, `amd64-vulkan` image repos exist upstream. Railway has no GPU runtime, so only the CPU image is used. |

## Runtime facts (verified by running the pinned image)

| Item | Value |
|---|---|
| Listener | Next.js standalone `node --enable-source-maps server.js`; `PORT` (default 8001), `HOSTNAME` (image default `0.0.0.0`) |
| Internal service | Readium server on `127.0.0.1:${READIUM_PORT}` (image default 9000); not exposed |
| Process model | image `ENTRYPOINT entrypoint.sh` runs as root, fixes ownership of `/data` for `PUID:PGID` (default 1000:1000), then `exec gosu storyteller tini -- node …` |
| Database | SQLite (`/data/storyteller.db`, WAL). Migrations run automatically at startup (`instrumentation.ts` → `migrate()`); startup aborts if they fail. The log line `SqliteError: no such table: migration` on a brand-new database is upstream's pre-migration check and is harmless. |
| Persistent paths | `/data` (`STORYTELLER_DATA_DIR`): `storyteller.db`, `assets/` (synced books, audio, covers), `uploads/`, `.autoimport/` (watch folder + watcher snapshots), `tmp/` (scratch, cleared at every start) |
| Health endpoint | `GET /api/health` → 200 `{"status":"healthy"}` only when the database has tables and the Readium service answers; 500 otherwise. Unauthenticated. |
| First run (upstream) | `/` redirects to `/init`, an **unauthenticated page that creates the administrator**. Anyone who reaches the URL first owns the instance. Once a user exists, `/init` redirects to `/`. |
| Auth | username/email + password (argon2id), bearer tokens (`POST /api/token`, form fields `username`/`password`), optional OAuth/OIDC providers (`authProviders` setting, `AUTH_URL` env). Invites for additional users; password reset needs SMTP. |
| Transcription engines | local whisper.cpp (bundled, CPU), remote whisper.cpp server, OpenAI-compatible cloud, Deepgram, Azure, Google, Amazon Transcribe — chosen in Settings. |
| Idle memory | ~340 MiB after first boot (local measurement) |
| Alignment cost | upstream minimums: up to 4 CPU cores, 8 GB RAM (12 GB swap suggested), ~10 GB disk; budget ~1 GB per book |
| Startup | ~20 s to healthy on a warm image; first deploy on Railway is dominated by pulling the 2.9 GB image |

## Environment variables (upstream, `applications/web/src/envSchema.ts`)

`STORYTELLER_SECRET_KEY` / `STORYTELLER_SECRET_KEY_FILE` (one required), `STORYTELLER_DATA_DIR`,
`STORYTELLER_DB_DIR`, `STORYTELLER_DB_FILENAME`, `STORYTELLER_ASSETS_DIR`, `STORYTELLER_SCRATCH_DIR`,
`STORYTELLER_SNAPSHOT_DIR`, `STORYTELLER_LOG_LEVEL`, `STORYTELLER_MAX_UPLOAD_CHUNK_SIZE`,
`STORYTELLER_INITIAL_AUDIO_CODEC`, `STORYTELLER_PASSWORD_RESET_EXPIRATION_MINUTES`,
`STORYTELLER_WHISPER_REPO`, `STORYTELLER_WHISPER_VERSION`, `STORYTELLER_WHISPER_VARIANT`,
`STORYTELLER_CONFIG` (declarative JSON that locks settings), `STORYTELLER_DEMO_MODE`,
`ENABLE_WEB_READER`, `READIUM_PORT`, `AUTH_URL`, `PUID`, `PGID`, `FORCE_USER_SETTING`.

## Backup and restore

- Storyteller has a built-in backup feature (Settings → Backups; `/api/v2/backups`) that writes
  archives under `/data`.
- Otherwise: stop the service, copy `/data` (database + assets) with
  `railway volume files download`, restore by uploading it back before starting.

## Upgrade and migration

- Schema migrations run at startup. Back up `/data` first.
- Upstream migration guides: `docs/migrations/from-v1-to-v2.md` and older (not applicable to fresh
  template deployments). v3 is in beta; do not move the template to `web-v3.*` until it is stable.

## Known Railway constraints

- One volume per service; single replica; brief downtime on redeploy.
- No GPU; alignment runs on CPU.
- Railway healthchecks run only at deploy time.
- Railway's template generator rejects `@sha256` image references; the template references the
  `web-v2.14.21` tag and this file records the digest.
