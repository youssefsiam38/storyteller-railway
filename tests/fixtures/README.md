# Test fixtures

- `gettysburg_address_lincoln_64kb.mp3` — LibriVox recording of Abraham Lincoln's Gettysburg Address
  (1863), read by a LibriVox volunteer. LibriVox recordings are released into the public domain
  (https://archive.org/details/gettysburg_address_librivox, licence
  http://creativecommons.org/licenses/publicdomain/). 2 min 41 s, 64 kbps, ~1.3 MB.
- `make-epub.py` — generates `gettysburg.epub`, a minimal EPUB 3 containing the public-domain text
  (Bliss copy), at test time; the EPUB itself is not committed.

They exercise upload, import, and a short bounded transcription + alignment run in `tests/smoke.sh`.
