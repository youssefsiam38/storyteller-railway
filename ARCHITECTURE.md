# Architecture

## Selected topology: one Railway service

```
          HTTPS (Railway edge)
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│ service: storyteller                                     │
│ image: ghcr.io/youssefsiam38/storyteller-railway:<ver>   │
│   (wraps registry.gitlab.com/storyteller-platform/       │
│    storyteller:web-v2.14.21)                             │
│ wrapper entrypoint (root) ─► upstream entrypoint         │
│   ─► gosu storyteller ─► tini ─► node server.js :PORT    │
│                                 └─ readium :9000 (loopback)│
│ volume: /data  (SQLite db, assets, uploads, scratch)     │
│ public domain → PORT (8001); healthcheck /api/health     │
└──────────────────────────────────────────────────────────┘
```

Storyteller is genuinely self-contained: SQLite database, local file library, in-process job
queue, bundled whisper.cpp and ffmpeg, and a Readium helper it starts itself on loopback. There is
nothing to split into separate services, and the app's working set (database + assets) must share
one filesystem, so a single volume-backed service is the production-correct shape.

## Why a wrapper image

The upstream image is Railway-ready except for one thing: on a fresh database the app serves an
**unauthenticated "create admin account" page** at `/init`, and Railway assigns the public domain
at deploy time. Whoever opens the URL first becomes the administrator. The wrapper closes that
window without touching application code:

1. Validates variables (secret key present, ≥32 chars; admin variables complete).
2. **First boot only:** starts the upstream entrypoint with `HOSTNAME=127.0.0.1`, waits for
   `/api/health` (migrations done), runs `bootstrap-admin.mjs` as the unprivileged `storyteller`
   user — it inserts the `user_permission` (all permissions) and `user` rows exactly as upstream's
   `createAdminUser()` does, hashing the password with the **same argon2 build the app uses**
   (`/app/.next/standalone/node_modules/argon2`), and seeds `webUrl` / `libraryName` only if they
   are empty — then stops the loopback instance.
3. `exec`s the upstream entrypoint on `0.0.0.0` (gosu + tini remain PID 1 lineage as upstream
   intends). Later boots detect existing users and skip step 2.

The bootstrap is idempotent, never prints values, and refuses to run if permissions rows exist
without users (an unexpected state worth inspecting). If no admin variables are set, the wrapper
refuses to start unless `STORYTELLER_ALLOW_OPEN_SETUP=true` is set explicitly.

## Health check

Railway healthcheck path: `/api/health`, timeout 600 s (the first deploy of a 2.9 GB image can be
slow). Upstream's route returns 200 only when the SQLite schema is present and the Readium helper
answers, so it is real readiness, unauthenticated, fast, and leaks nothing.

## Persistence and replicas

One volume at `/data`, one replica, brief downtime on redeploy. Alignment scratch space
(`/data/tmp`) is cleared at every start; queued jobs are resumed by upstream at startup.

## Resource shape

Alignment (transcription + forced alignment) is CPU- and memory-bound: upstream recommends up to
4 cores and 8 GB RAM. Railway bills for actual CPU/RAM, so long alignments cost while running.
Offloading transcription to a remote whisper.cpp server or a cloud provider (OpenAI-compatible,
Deepgram, Azure, Google, Amazon) is configured in Settings and reduces Railway CPU time.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Upstream image directly | open `/init` claim window on a public domain |
| Gateway password (basic auth) in front until setup | extra proxy, breaks the mobile apps' API auth, and still leaves the admin creation to a manual step |
| Keep the service private until the owner enables a domain | Railway templates create the domain with the service; users expect a working URL immediately |
| Separate PostgreSQL/Redis | not used by upstream (SQLite + in-process queue) |
| GPU images | no GPU runtime on Railway |
