# CouchDB

CouchDB 3.x sync backend for Obsidian notes. Key constraint: CouchDB 3.x replaced the 2.x compaction daemon with **smoosh** — configs from 2.x are silently ignored.

## Compaction

CouchDB 3.x uses the smoosh daemon for automatic compaction. The old `[compaction_daemon]` + `[compactions]` sections from CouchDB 2.x are **silently ignored** in 3.x — this was the root cause of fragmentation accumulating undetected.

Smoosh thresholds configured in `local.ini` under `[smoosh.ratio_dbs]`:
- `min_priority = 1.25` → compact when `file/active > 1.25` (~20% fragmentation)
- `slack_dbs min_priority = 209715200` → compact when wasted space > 200MB

Why these thresholds: default smoosh requires ratio ≥ 2.0 (50% frag) or 512MB slack — too lenient for a server with limited disk space.

## Data Size vs Vault Size

Obsidian LiveSync stores vault files as base64-encoded chunks in CouchDB documents (not as CouchDB attachments). Expected overhead:
- Base64 encoding: +33% vs raw binary
- Chunk metadata documents: additional ~5-10%
- Total: CouchDB `external` size ≈ 1.4x vault size on disk

If `external` >> 1.4x vault size → orphaned chunks exist → run LiveSync Housekeeper in Obsidian plugin settings.

## Fragmentation Monitoring

Fragmentation = `(file - active) / file * 100`. Fields from `GET /{db}`:
- `sizes.file` — total `.couch` file size (includes dead revisions)
- `sizes.active` — bytes used by current document versions
- `sizes.external` — uncompressed JSON size of all current docs

After compaction, `file ≈ active`. Fragmentation accumulates when documents are updated frequently (Obsidian sync = high write frequency per device).
