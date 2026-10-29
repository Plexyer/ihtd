# Portable .ihtd document storage

## Required safety for upcoming migrations

The owner-approved [migration safety prerequisite](changes-2026-10-28.md#14-migration-safety-prerequisite)
requires a verified backup beside the original collection or in an authorized
backup folder before migrating, a separately validated candidate before guarded
publication, and automatically persisted/exportable redacted failure logs.
The shared implementation and remaining physical acceptance are described in
[migration safety](migration-safety.md). Current schema-2 files need no conversion;
legacy schema-1 files pass the verified-backup/candidate gate before model open.

## Format and publication

An .ihtd document is a self-contained SQLite file with application ID
0x49485444 and schema version 2. Version 1 files require a verified backup, migrate through a separate validated
candidate, and publish through the guarded coordinator. Direct model open refuses
an old schema; it cannot defer an unprotected conversion to the next edit. Older apps reject the new format. Ordered
root placements are stored as root_order metadata, so a shared item can be
at the top level and under another parent simultaneously. Tables contain metadata, items, tags, views,
and ordered links. Each item occurs once in storage; views render its
placements. Metadata includes a document UUID, monotonic revision, and next ID.

Rust keeps the active document in memory. Each accepted command mutates and
validates a candidate clone, then creates a closed SQLite snapshot in local
temporary storage. No live SQLite connection opens the user's mounted path.

Publication writes and flushes a temporary sibling before atomically replacing
the destination through tempfile::persist. There is no truncate-in-place
fallback. A mount's replacement/durability guarantees still depend on its
filesystem implementation. On Unix the parent directory is also synced.

Before publication a recovery snapshot is retained under the app's support
directory/recovery. It is a complete .ihtd file, not history. Failure after
that point preserves the pending in-memory state and recovery file. Retry
attempts publication; Save a copy writes to a new path. A failure before
acceptance leaves the original document intact and reports the error.

## External changes

The controller polls every three seconds and on focus. SHA-256 of file contents
detects replacements even if file size and timestamps did not change. Changed
bytes are decoded and validated in local temporary storage. Only a strictly
newer revision of the same document is automatically adopted, and only without
pending unpublished changes.

Corrupt, older, unrelated, and equally numbered divergent documents produce
an error without discarding the valid open state. Mutations recheck the
baseline before publication. Editor revisions and field comparisons prevent
stale drafts from silently replacing an externally updated item.

These checks are not a distributed lock. A remote edit hidden by a sync
client's cache cannot be detected yet, and a race after the final check is
possible. This prototype therefore supports only one editing device at a time.
“Saved” means the chosen filesystem accepted the write, not that a cloud
provider finished uploading it.

## Recovery

The local recovery directory is inside the platform application-support
directory chosen by path_provider. Recovery files have hashed names ending
in .ihtd. They can be opened through the normal file picker and saved to a new
location. There is no automatic recovery browser or revision-history UI.
Use the error banner and Retry/Save a copy while the app remains open.

## Verified coverage

Tests cover document round trips, shared identity, single-file snapshots,
changed content with unchanged size/timestamp, rejection of external changes
before saving, preservation of valid state after corrupt replacement, refusal
to overwrite during New/Save a copy, failed replacement keeping its
destination intact, and Save a copy preserving pending state.

References:
- https://www.sqlite.org/appfileformat.html
- https://www.sqlite.org/useovernet.html
- https://docs.rs/tempfile/latest/tempfile/struct.NamedTempFile.html#method.persist
