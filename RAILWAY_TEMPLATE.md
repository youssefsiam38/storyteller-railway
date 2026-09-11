# Deploy and Host Storyteller

Storyteller turns an ebook plus its audiobook into a read-along book: it transcribes the narration,
aligns every sentence with the text, and produces EPUB 3 books with synchronised highlighting. Read
in the Storyteller iOS/Android apps or the web reader, switch between reading and listening, and
never lose your place. It is the self-hosted alternative to Kindle/Audible Whispersync and
immersion reading, for books you own. This is a community-maintained template, not affiliated with
the Storyteller project.

## About Hosting

One Railway service, `storyteller`, runs the official Storyteller image
(`registry.gitlab.com/storyteller-platform/storyteller:web-v2.14.21`) through a thin wrapper
(`ghcr.io/youssefsiam38/storyteller-railway`, version-specific tag with recorded digest). The
wrapper creates the administrator from generated variables **before** the service is exposed, so
Storyteller's normal "create admin account" first-run page is never reachable by strangers. The
service gets the public HTTPS domain and one volume at `/data` for the SQLite database, uploads,
and the aligned library. The healthcheck is Storyteller's own `/api/health`, which reports ready
only when the database and the Readium helper are up. Schema migrations run automatically at
start. Single replica; a few seconds of downtime on redeploy.

## Why Deploy

- Synchronised reading and listening for books you own, on your own server, with the open
  EPUB 3 Media Overlay format instead of a vendor lock-in.
- No claimable setup page: the admin exists before the URL works, with a generated password.
- Everything Storyteller needs (whisper.cpp, ffmpeg, Readium) is in the image; no extra services.
- Pinned versions (never `latest`); upgrades are explicit.

## Common Use Cases

- Read along with a narrator: dyslexia and language-learning support, kids' books, dense
  non-fiction.
- Commute listening, evening reading: pick up exactly where the other mode left off.
- Family library shared through invites, with OPDS for other reader apps.

## Dependencies for Storyteller

- Your own DRM-free EPUBs and audiobook files (MP3, M4B, etc.).
- Optional: an SMTP account for invite and password-reset emails; optional cloud transcription
  provider (OpenAI-compatible, Deepgram, Azure, Google, Amazon) to cut CPU time.

### Deployment Dependencies

- A Railway plan with volumes and enough CPU/RAM for alignment (upstream recommends up to 4 cores
  and 8 GB RAM while a book is processing).
- One value entered at deploy time: `STORYTELLER_ADMIN_EMAIL`.
- Source and documentation: https://github.com/youssefsiam38/storyteller-railway
- Upstream project: https://gitlab.com/storyteller-platform/storyteller (MIT)

## After Deploying

1. Wait for the service to be healthy. The first deploy pulls a 2.9 GB image.
2. Open the public URL and sign in with username `admin` and the generated password shown in the
   `storyteller` service variable `STORYTELLER_ADMIN_PASSWORD` (dashboard → Variables).
3. Change your password in your account; check Settings → Web URL matches your domain.
4. Upload a book (EPUB + audio). Processing starts automatically; alignment is CPU-bound and can
   take a long time for full audiobooks. Consider a cloud transcription provider in Settings.
5. Install the Storyteller apps and sign in with your server URL. Invite others from Users.

Resource expectations: about 340 MiB memory idle, multiple GB and several CPU cores while a book
is aligning, ~1 GB of volume per book. Limitations: single replica; CPU-only transcription; the
generated admin password stays in a Railway variable until you change it in the app.
