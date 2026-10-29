# Collection migration safety

Implementation candidate, 2026-10-28. This implements the first prerequisite in
[the agreed order](FEATURE_CHECKLIST.md#implementation-order). Physical upgrade
acceptance on Pixel/GrapheneOS, Samsung, Windows and Fedora is still required.
It does not implement the later editor, linking, sorting or settings features.
The app version and release tags are unchanged.

## Shared flow

`MigrationSafety` in Flutter owns the policy, backup authorization, durable
attempt records, failure diagnostics and recovery access. `DocumentSaveCoordinator`
continues to own external identity/baseline checks, publication and read-back.
`crates/ihtd_app/src/migration.rs` supplies read-only detection and pure candidate
conversion/validation. `MigrationBackupAdapter` provides native folder selection
and create-new backup access; it cannot approve or publish a migration itself.

1. Stage the selected document privately and inspect its format without opening
   a mutable model session. Current schema-2 collections, including files from
   0.2.5, need no conversion and request no migration backup/folder permission.
   Schema 1 needs conversion; unsupported/corrupt/WAL snapshots are refused.
2. Save the attempt and source references privately. Check the selected external
   file's current hash, name and available identity against its opening baseline.
3. Create a uniquely named `IHTD-before-upgrade-<attempt>-<role>.ihtd` backup.
   Desktop defaults to a sibling of the original (the selected symlink's actual
   target). Android uses an explicitly authorized document-tree folder; select
   the original file's folder when the provider permits it. The tree grant and
   selected backup destination are retained. A different authorized folder can
   be chosen from upgrade details, including on desktop after a sibling failure.
4. Close/flush the backup and read it back. Compare both its fingerprint and
   complete bytes with the intended closed source snapshot. Refuse an existing
   destination/alias, a failed write, unavailable folder or failed verification.
   Never silently substitute an app-private *collection backup*.
5. Back up retained unpublished working data and recovery files separately,
   including recovery discovered from the original path/collection identity.
   Original private files remain unchanged. Their backup is not replaced by an
   older copy of the external file. If the external baseline is unavailable or
   changed, stop rather than publish local work over it.
6. Convert each necessary store into a separate private candidate. Validate
   SQLite integrity and full model equality: identities, revision, next ID,
   items/fields, tags, views/preferences, links/order and deletion metadata.
   Also compare the stored representation, so unknown fields/tables/columns or
   metadata cannot disappear unnoticed during deserialization. Refuse unknown
   extensions rather than discard them. Candidate open checks the validated
   hash again inside Rust before accepting its bytes.
7. Open the validated private candidate. Fresh external opens publish the
   migration through the normal guarded coordinator. Restored/pending sessions
   retain the existing explicit-confirmation and recovery barriers. Record the
   publication intent before a provider write; only read-back plus durable
   registry persistence can complete the attempt.
8. Retain the original, backup and candidate after success. On failure stop
   that attempt's writes. On restart, record unfinished attempts as interrupted;
   never replay provider writes automatically. A fresh explicit retry uses a
   different attempt/backup. Successful retry marks earlier failures for that
   same external reference resolved, without deleting their files/logs. Explicitly reopening an external file that
   exactly matches a previously validated candidate can also reconcile a write
   that completed but reported failure. A partial/different file cannot clear the
   barrier this way, and no write is replayed during reconciliation.

`Session::open`, recovery restore and external reload refuse old-schema data,
so direct model loading cannot silently bypass the backup gate. Schema decoding
used for migration validation remains read-only. Private registry upgrades to
schema 3 also keep verified JSON backups beside their original metadata,
validate a separate serialized candidate, and automatically log conversion
failures. They preserve old working/recovery paths and unknown registry fields.
Future registry versions are refused rather than downgraded.

SQLite collections produced by IHTD are closed, self-contained snapshots.
Desktop reads refuse adjacent journal/WAL/SHM files; format inspection also
refuses WAL-mode headers. A provider grants access to a document, not necessarily
its sidecars, so Android cannot prove facts about inaccessible sibling journals.
Use complete IHTD snapshots; do not feed it an active database from another writer.
No conversion connects SQLite directly to a provider/mounted original.

## Failure information and recovery

The shared status opens upgrade details even when no collection opened.
Missing authorization/external change uses a yellow warning; failed validation,
private persistence or publication uses red. Details explain the stage and safe
next steps, list verified backup locations and allow choosing another authorized
backup folder. Opening the details does not retry a write.

**Upgrade recovery files** offers original working files, external snapshots,
recovery and candidates as separate user-selected exports. Existing external
files cannot be overwritten by these exports. **Retained working copies** and
normal **Open collection** remain available. To retry an unchanged original,
resolve storage/access problems and explicitly open it again. To inspect an old
backup, open it separately; its original bytes remain protected through another
backup/candidate pass. Never blindly restore a backup over newer external edits.
Successful attempts/backups are also inspectable through Advanced details.

The private `documents/migrations` directory retains per-attempt JSON journals
and **automatically created** `<attempt>.failure.json` logs. Journals have private
recovery locations and are not exported as diagnostic logs. Default diagnostic
export contains only allowlisted app/build/OS versions, format versions, stage
and stage times, sanitized codes, non-content validation counts and anonymous
attempt/backup references. It excludes titles, notes, tag names, document IDs,
SQL/exception text, filenames, full paths/URIs and credentials. Nothing uploads
logs automatically. If log persistence fails, the UI says so and migration stays
stopped; export must not claim a current log exists.

Provider close/flush and read-back establish the guarantees the provider exposes,
not remote cloud synchronization or hardware immunity to power loss. Desktop
backups flush their file and, on Unix, directory metadata. SAF final publication
can be non-atomic: a failure may leave an incomplete external file, which is why
backups, private candidates and persisted write barriers are retained. Ordinary
conflict checks still cannot provide a cross-device distributed lock.

## Adding later data-changing features

- Extend the shared read-only probe and explicit conversion plan **before**
  changing existing stored data, including semantic conversions without a schema
  bump. `needed` is a plan decision, not permission to silently normalize data in
  a model loader. UI-only work needs no artificial migration.
- Specify the allowed changes/defaults and preservation checks for that plan;
  update the raw-storage comparison when an approved conversion intentionally
  changes a representation. Do not weaken it to silently ignore unknown data.
- Protect every existing store that will be transformed, preserve pending
  recovery, use fresh candidate identities/paths and retain originals/backups.
- Add frozen previous-format fixtures and failure injection for the new plan.
  This implementation only contains the existing schema-1-to-2 conversion and
  legacy registry conversion. A future schema/data conversion needs its own
  implementation and acceptance; it is not automatically proven by this task.

## Automated verification

- `cargo test --workspace --locked`: read-only detection, old-session gate,
  frozen schema-1/schema-2 fixtures, rich linked model/preferences, exact field
  preservation, unknown-field rejection, candidate hash checks, stale baselines,
  sidecars/WAL/corruption and refusing to overwrite a candidate.
- `flutter test test`: shared adapter scenarios for backup/grant refusal,
  write/read-back/validation failures, separate unpublished/recovery backups,
  interruption, safe retry, external replacement, partial publication, persisted
  redacted logs and unavailable diagnostic storage. Registry retry tests verify
  the exact old JSON backup and original paths remain present.
- `flutter test integration_test/migration_test.dart -d linux` (or Windows):
  real Rust/Flutter filesystem migration of a frozen legacy fixture, byte-exact
  sibling backup, preserved contents, guarded publication and restart.
  Windows/Fedora native pipelines now include this test.
- Kotlin `:app:testDebugUnitTest`: strict new-empty backup destinations, source
  alias rejection, conflict checks, failed/partial writes and read-back.
- Existing desktop UI integration and shared architecture/release tests remain
  part of regression verification. Tests use synthetic files, never user data.

## Cloud verification record — 2026-10-28

Passed: 72 Rust tests, 155 Flutter tests, Flutter analysis, 17 Python checks,
9 Kotlin tests and Android Kotlin compilation, real Linux migration/restart
integration, and the existing Linux desktop UI integration. Final migration/
controller/popup regression checks also passed after the restart/reconciliation
changes. An ARM64 Android release candidate built successfully; all four native
libraries and the APK ZIP passed their separate 16 KB alignment checks.

No Windows/Fedora native runner or physical phone was exercised in this cloud
workspace. Installation binaries/signing material are not committed, and the
candidate is not a new production release. Device acceptance below stays open.

## Physical acceptance before a data-migrating release

Use **copies** of important collections, retain an independent known-good backup,
and test both the Pixel/GrapheneOS and Samsung. Also exercise Windows and Fedora
local/removable/mounted storage through their native packages.

1. Upgrade a representative 0.2.5 schema-2 collection: it opens unchanged, without
   an unnecessary conversion or folder prompt. Check tasks, notes, tags, dates,
   priority/completion, custom views, links/order and preferences.
2. Open the legacy fixture (rename a copy to `.ihtd`) and, for a future feature
   migration, that feature's previous-format fixture. Authorize the containing
   or chosen backup folder. Verify the retained backup is pre-conversion and
   the published collection has all expected data. Restart/reopen the app.
3. Repeat with unpublished edits and a newer recovery copy. Verify independent
   external/working/recovery backups and no automatic overwrite on restoration.
4. Cancel/deny/revoke backup-folder access; test full/unavailable storage and
   failed/read-only providers. Verify conversion is blocked, the source unchanged,
   a readable warning and automatic private log (or explicit logging failure).
5. Interrupt at backup, conversion and final publication. Restart: inspect the
   interrupted attempt, export the log and recovery copies, and verify no
   automatic provider rewrite. Check behavior when the OS terminates the process.
6. Rename/replace/edit the external file while preparation or confirmation is
   pending. Verify it is not overwritten; use explicit review/reopen/save-copy.
7. Retry safely after resolving the cause. Older backups remain, the attempt
   completes once, and existing user data/recovery survives app installation.

Host tests do not establish those physical-device, provider or power-loss results.
