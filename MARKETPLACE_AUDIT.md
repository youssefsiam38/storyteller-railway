# Marketplace gap audit

Audit of the Railway Marketplace for an existing Storyteller (or equivalent ebook + audiobook
alignment / read-along) template.

- **Audit timestamp (UTC):** 2026-09-11T16:22:31Z (initial); pre-publication rerun recorded below
- **Tool:** `npx -y @railway/cli@latest templates search "<query>" --json --limit 50` (Railway CLI 5.52.1)
- **Secondary:** web search for `site:railway.com` plus product name and aliases

## Queries and results

| # | Query | Class | Result |
|---|---|---|---|
| 1 | `storyteller` | exact product name | 0 results |
| 2 | `whispersync` | commercial feature it replaces | 0 results |
| 3 | `audiobook ebook` | generic need | 0 results |
| 4 | `ebook audiobook sync` | generic need | 0 results |
| 5 | `read along` | generic need | 0 results |
| 6 | `immersion reading` | commercial alias (Kindle) | 0 results |
| 7 | `narrated ebook` | generic need | 0 results |
| 8 | `smoores` | former maintainer namespace | 0 results |
| 9 | `audiobook` | adjacent category | 7 results: Audiobookshelf (×4 listings), Booklore, Grimmory, Bookorbit |
| 10 | `ebook` | adjacent category | 9 results: Calibre-Web, Calibre, Grimmory, Bookorbit, Audiobookshelf, Kavita (×2), Komga (×2) |

### Adjacent matches inspected

| Template | Code | What it is | Overlap with Storyteller |
|---|---|---|---|
| Audiobookshelf | `audiobookshelf`, `audiobookshelf-serverless`, `audiobookshelf-1`, `audiobookshelf-railway` | audiobook and podcast server with progress sync | none: plays existing audiobooks; does not align an ebook's text with narration |
| Booklore | `booklore` | book and audiobook library manager | none: metadata/library management |
| Grimmory | `grimmory-digital-library`, `grimmory` | ebook/comic/audiobook library with Kobo sync | none |
| Bookorbit | `bookorbit-server` | private library for ebooks/audiobooks/comics/PDFs | none |
| Calibre-Web, Calibre, Kavita, Komga | various | ebook/comic readers and servers | none: no audio alignment |

None of these produce synchronised read-along (EPUB 3 Media Overlay) books from an ebook plus an
audiobook, which is Storyteller's purpose.

### Web search

`site:railway.com storyteller ebook audiobook sync template deploy` returned only the adjacent
templates above (Audiobookshelf, Grimmory, Bookorbit, Calibre-Web, Booklore). No Storyteller page.

## Conclusion (initial audit)

**Clean gap.** No exact or alias match; adjacent templates solve library/playback, not alignment.
Proceeding with Storyteller.

## Re-audit before publication

| Timestamp (UTC) | Queries | Result |
|---|---|---|
