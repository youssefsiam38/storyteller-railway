# Third-party notices

Original wrapper code (Dockerfile, `scripts/`, tests, CI, docs) is MIT licensed (`LICENSE`). The
published image redistributes the upstream image unchanged plus these scripts.

| Component | Version | License | Source | Notice in image |
|---|---|---|---|---|
| Storyteller (web application and libraries) | web-v2.14.21, commit `fbf6d83ff289e106e1c44bf48aeb325722d160e9` | MIT, © 2023 Shane Friedman | https://gitlab.com/storyteller-platform/storyteller | `/usr/share/licenses/storyteller-railway/STORYTELLER-LICENSE` (also `licenses/STORYTELLER-LICENSE` here) |
| Storyteller runtime dependencies (Next.js, Kysely, better-sqlite3, argon2, next-auth, echogarden, kuromoji, and others) | as bundled | various OSI licenses per package (`yarn.lock` upstream) | upstream monorepo | inside `/app/.next/standalone` as shipped |
| whisper.cpp binaries and `tiny.en` model | v1.8.2 | MIT (whisper.cpp); OpenAI Whisper model weights, MIT | https://github.com/ggerganov/whisper.cpp | as shipped upstream |
| Readium (readium-cli / go-toolkit) | 0.6.5 | BSD-3-Clause | https://github.com/readium/go-toolkit | `/opt/readium` as shipped upstream |
| ffmpeg | as bundled | LGPL/GPL (build-dependent) | https://ffmpeg.org | as shipped upstream |
| Node.js / Ubuntu base | 24.8.0 / 24.04 | MIT and others / various | upstream `storyteller-base` image | as shipped upstream |
| gosu, tini, sqlite3 | Ubuntu packages | Apache-2.0 / MIT / Public Domain | Ubuntu archive | as shipped upstream |

Test fixtures: `tests/fixtures/gettysburg_address_lincoln_64kb.mp3` is a LibriVox public-domain
recording (https://archive.org/details/gettysburg_address_librivox); the text (Lincoln, 1863) is
public domain.

"Storyteller" is the upstream project's name; "Whispersync", "Audible", and "Kindle" are trademarks
of their owners, used only descriptively. This template is community maintained and not affiliated
with the Storyteller project, Amazon, or Railway.
