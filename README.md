# Storyteller on Railway

Turn an ebook and its audiobook into a **read-along book**: Storyteller transcribes the narration,
aligns it with the text, and produces EPUB 3 books with synchronised highlighting that you read and
listen to in its iOS/Android apps or the web reader, switching between reading and listening
without losing your place. It is the self-hosted answer to Kindle/Audible "Whispersync" and
immersion reading. This repository is a **community-maintained Railway template** for
[Storyteller](https://storyteller-platform.dev). It is **not affiliated with the Storyteller
project**.

<!-- DEPLOY_BUTTON_START -->
_Deploy button will appear here after the template is published._
<!-- DEPLOY_BUTTON_END -->

## What you get

| Service | Image | Public | Volume |
|---|---|---|---|
| `storyteller` | `ghcr.io/youssefsiam38/storyteller-railway:<version>` wrapping `registry.gitlab.com/storyteller-platform/storyteller:web-v2.14.21` | yes (Railway domain, HTTPS, port 8001) | `/data` — SQLite database, library assets, uploads, scratch |

| Component | Version |
|---|---|
| Storyteller web | v2.14.21 (commit `fbf6d83`) |
| whisper.cpp (bundled, CPU) + model | v1.8.2, `tiny.en` |
| Readium | 0.6.5 |
| Node.js / base | 24.8.0 / Ubuntu 24.04 |
| Wrapper | see [releases](https://github.com/youssefsiam38/storyteller-railway/releases) |

What the wrapper adds and why: [ARCHITECTURE.md](ARCHITECTURE.md). In one sentence: Storyteller
normally shows an unauthenticated "create admin account" page on first run; the wrapper creates
the administrator from generated variables **before** the service is reachable.

## First run (about 5 minutes after the image is pulled)

1. Click **Deploy on Railway**. Enter your email address (it becomes the administrator's email).
   Everything else is generated. The first deploy pulls a 2.9 GB image; allow several minutes.
2. When the service is healthy, open its public URL. You land on the login page.
3. Sign in with the generated credentials: username `admin` (variable
   `STORYTELLER_ADMIN_USERNAME`) and the password stored in the service variable
   `STORYTELLER_ADMIN_PASSWORD` (Railway dashboard → `storyteller` → Variables → click to reveal).
4. Go to your account and set a password you will remember. Optionally set a library name and
   check that the Web URL in Settings matches your domain (the wrapper seeds it from the Railway
   domain).
5. Add a book: upload an EPUB and its audiobook files (Library → Add). Processing (transcription +
   alignment) starts automatically and can take a while on CPU; watch the status on the book.
6. Install the [Storyteller apps](https://storyteller-platform.dev/docs/reading/storyteller-apps)
   and sign in with your server URL.
7. Invite family or friends from Users → Invites (needs SMTP in Settings to email the invite, or
   copy the invite link).

## Environment variables (`storyteller` service)

| Variable | Required | Set by template | Description |
|---|---|---|---|
| `STORYTELLER_SECRET_KEY` | yes | generated `${{secret(64, "abcdef0123456789")}}` | Signs auth tokens and encrypts stored credentials. Changing it invalidates sessions and stored provider secrets. |
| `STORYTELLER_ADMIN_USERNAME` | yes | `admin` | Administrator username created on first boot (lower-cased). Ignored once a user exists. |
| `STORYTELLER_ADMIN_PASSWORD` | yes | generated `${{secret(24)}}` | Administrator password created on first boot (min 12 chars). Reveal it in the dashboard to log in the first time, then change it in the app. |
| `STORYTELLER_ADMIN_EMAIL` | **yes, you** | — | Administrator email (account record; used for password reset and OAuth account linking). |
| `STORYTELLER_ADMIN_NAME` | no | `Administrator` | Display name. |
| `STORYTELLER_WEB_URL` | no | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Seeds the "Web URL" setting on first boot only. Change the setting in the app afterwards (e.g. custom domain). |
| `STORYTELLER_LIBRARY_NAME` | no | `My Library` | Seeds the library name on first boot only. |
| `PORT` | yes | `8001` | Listening port (Railway routes the domain to it). |
| `STORYTELLER_LOG_LEVEL` | no | `info` | `error`, `warn`, `info`, `debug`, `trace`. |
| `STORYTELLER_MAX_UPLOAD_CHUNK_SIZE` | no | upstream default `10` | Upload chunk size in MB. |
| `STORYTELLER_INITIAL_AUDIO_CODEC` | no | unset | `mp3`, `aac`, `opus[-16|24|32|64|96]` for the initial audio conversion. |
| `AUTH_URL` | no | unset | Required only when you configure OAuth/OIDC providers in Settings; set it to your public origin. |
| `PUID`, `PGID` | no | `1000` | Unix ids the app runs as. Leave at defaults on Railway. |
| `STORYTELLER_ALLOW_OPEN_SETUP` | no | unset | Set `true` only if you deliberately want upstream's open first-run page instead of the bootstrapped admin. Not recommended on a public URL. |
| `APP_READY_TIMEOUT` | no | `300` | Wrapper: seconds to wait for the loopback instance during first-boot bootstrap. |

Transcription engine, SMTP, OAuth providers, OPDS, backups, and import rules are configured in
the app's Settings (stored in the database), not as variables. Upstream's `STORYTELLER_CONFIG`
declarative file is not used by the template so that Settings stay editable in the UI.

## Persistent paths

| Path | Contents | Backup |
|---|---|---|
| `/data/storyteller.db` (+ `-wal`, `-shm`) | users, books, settings, jobs | app Backups feature or copy while stopped |
| `/data/assets` | synced books, audio, covers | copy |
| `/data/uploads`, `/data/.autoimport` | uploads and watch folder | copy |
| `/data/tmp` | alignment scratch, cleared at every start | not needed |

Budget roughly 1 GB of volume per book (source files, converted audio, aligned output). Railway
volumes can be grown but not shrunk.

## Public routes

| Route | Auth | Purpose |
|---|---|---|
| `/` → `/login` | no | web UI |
| `/init` | — | redirects to `/` once the administrator exists (wrapper guarantees this before exposure) |
| `/api/health` | no | **Railway healthcheck**: 200 only when the database schema and Readium helper are up |
| `/api/token`, `/api/v2/*` | token | REST API used by the apps |
| `/opds/*` | token/basic | OPDS catalog (optional) |

Only port 8001 is public. The Readium helper listens on loopback only.

## Run locally

Requires Docker with Compose v2, `curl`, `jq`, `python3`, `node` (for a syntax check in the static
tests). The compose stack mirrors the Railway service with one named volume.

```bash
docker compose build
docker compose up -d
# http://localhost:8001  (admin / local-test-only-admin-password)
```

Tests:

```bash
tests/static.sh         # shellcheck, node/python syntax, compose config, pinned tag+digest, SHA-pinned actions
tests/smoke.sh          # empty volume → bootstrap → login → /init not claimable → upload EPUB+MP3 → job starts → SIGTERM, child death, fail-fast checks
RUN_ALIGNMENT=1 tests/smoke.sh   # additionally waits (bounded) for the 2 min 41 s public-domain test book to align
tests/persistence.sh    # book, settings and admin survive container recreation; bootstrap is skipped
tests/railway-smoke.sh https://your-app.up.railway.app   # public checks against a deployment
```

## Backup and restore

- In-app: Settings → Backups creates archives under `/data`; download them from the volume.
- Whole volume: `railway volume files download --service storyteller /data ./storyteller-data`
  while the service is stopped (SQLite WAL must be quiescent) and upload it back to restore.

## Upgrades

Each wrapper release pins one Storyteller `web-v*` tag (and records its digest). Schema migrations
run automatically at startup; take a backup first. v3 is in beta upstream and is not used until
stable. Maintainer process: [MAINTENANCE.md](MAINTENANCE.md).

## Resource use and cost

Railway bills CPU, memory, volume storage, and egress ([pricing](https://railway.com/pricing)).

| Metric | Value |
|---|---|
| Image | ~2.9 GB uncompressed; first deploy is dominated by the pull |
| Idle memory | ~340 MiB (local measurement, first boot) |
| Startup | ~20 s to healthy on a warm image (first boot includes the admin bootstrap) |
| Alignment | CPU-bound: upstream recommends up to 4 cores and 8 GB RAM; a 2 min 41 s test clip transcribes in seconds and aligns in about a minute on 4 CPU cores with the bundled `tiny.en` model; full audiobooks take hours of CPU time |
| Storage | ~1 GB per book |

Cost drivers: CPU time during alignment (the big one), memory during transcription, volume size,
and egress when the apps download books. To cut Railway CPU time, offload transcription to a
remote whisper.cpp server or a cloud provider in Settings.

## Security

- The administrator is created before the service is exposed; there is no claimable setup page.
- Sign in once with the generated password from the Railway variables, then set your own.
- Invites are the only way to add users; there is no open registration.
- Secrets are generated per deployment and never logged by the wrapper.
- Report wrapper issues via [SECURITY.md](SECURITY.md).

## Known limitations

- Single replica; brief downtime on redeploy; one volume.
- CPU-only transcription; no GPU on Railway.
- The generated admin password lives in a Railway variable until you change it in the app.
- Railway healthchecks run at deploy time only.
- `linux/arm64` images are published because upstream ships arm64; only `amd64` is tested here.

## Legal use

Upload only ebooks and audiobooks you own and are permitted to convert; DRM-protected files are
not supported and must not be stripped. Your instance stores your users' reading data; you are
responsible for it.

## Links

- Upstream: https://gitlab.com/storyteller-platform/storyteller (MIT) · Docs: https://storyteller-platform.dev
- Wrapper image: https://github.com/youssefsiam38/storyteller-railway/pkgs/container/storyteller-railway
- [LICENSE](LICENSE) · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [UPSTREAM.md](UPSTREAM.md) · [MARKETPLACE_AUDIT.md](MARKETPLACE_AUDIT.md)
