# Protected All tasks view

Implementation candidate, 2026-10-31. Implements step 9 / item 1 in the
[owner's backlog](FEATURE_CHECKLIST.md#implementation-order). Physical upgrades
on Pixel/GrapheneOS, Samsung, Windows and Fedora remain open; the app version
and release tags are unchanged.

## Shared behavior

Rust identifies and protects one built-in view. It is named `All tasks`, uses
`FilterExpr::All`, and cannot be renamed, filtered or deleted. Both backend
commands and shared Flutter UI enforce this. Its information button explains
these limits without resolving or committing an unfinished item draft. Sorting,
visibility/display preferences and editing the actual tasks/folders remain
available. The sidebar puts the built-in first and keeps custom views in their
existing order. Opening another working collection selects its protected ID,
including when that collection shares a UUID with another copy.

The snapshot supplies `all_tasks_view_id`; consumers must not assume it is 1.
An explicit stored marker must point to an existing, intact built-in. Invalid
markers are refused as corrupt instead of silently reset.

## Compatibility and allowed migration

| Existing file | Opening behavior |
| --- | --- |
| Original view 1 is named exactly All tasks and has an All filter | Infer its protected identity; no semantic conversion, rewrite or new backup permission |
| Original view was renamed, filtered, deleted, or all views were deleted | Require the explicit protected-view semantic migration |
| A migrated file contains a valid explicit marker | Keep that protected ID; no repeated semantic conversion |
| Schema 1 | Run the existing format migration, combining protected-view installation if needed |
| Explicit marker is invalid, or snapshot/format is unsupported/corrupt | Refuse safely and retain source; no silent repair |

No arbitrary user-created view is repurposed by name. When migration is needed,
all existing views—including the customized original and similarly named custom
views—remain unchanged. A separate built-in receives the next available global
ID, empty view preferences/sorting, and an optional `all_tasks_view_id` metadata
entry. Only existing model counters `next_id` and `revision` increment once. The
encoder may serialize known defaults without changing their values. Schema remains 2 for the
semantic plan. Intact original files keep the marker absent, avoiding a rewrite
just to open or identify the view.

The explicit plans are `protected-all-tasks`, `schema-1-to-2`, and
`schema-1-to-2-and-protected-all-tasks`. The probe's `needed` flag governs the
shared migration gate, even when source and target schema numbers are both 2.
Model loading never installs the missing view. Session open, external reload
and recovery restore reject an unconverted customized/missing built-in.

Follow [migration safety](migration-safety.md): verify a create-new backup beside
the external file or in an authorized folder before conversion. Independently
back up retained working/recovery files. Convert separate candidates, validate
SQLite integrity, full expected-model equality and raw stored-data preservation,
then publish through existing identity/baseline/read-back safeguards. Unknown
fields/tables/columns/metadata that cannot be preserved stop conversion.
Exhausted IDs/revisions fail atomically. View installation does not recompute
unrelated stored completion fields. Preserve items, tags/history, settings,
existing views/preferences/sorts, deleted IDs, shared links and manual order.

Original private files, candidates and backups remain retained. Backup refusal,
failed conversion/publication or interruption blocks unsafe writes and produces
the existing automatic redacted failure log; logs now also include only
allowlisted plan names, so a semantic schema-2-to-2 failure is identifiable.

## Pending edits and private drafts

Restored pending working/recovery sessions keep their external confirmation
barrier. An upgrade must not publish previously unpublished edits automatically.

The private migration journal records each validated candidate's exact source
path/hash. On explicit Restore, an unfinished item draft may follow that mapping
to the current candidate only with unchanged source evidence and matching
collection identity. The controller checks the owner again after asynchronous
verification. UUID equality alone, an unrelated working path, or changed/missing
source evidence never authorizes rebinding. Restore preserves editable fields,
baselines and the original custom creation view. The migration's private source digest recognizes an exact pre-conversion
Save receipt without replaying it. For a creation proven unaccepted in the source,
the obsolete proposed ID is cleared in memory only if it is now the active
protected view's ID. A newer recovery that consumed the ID for an actual item
cannot qualify; it keeps the ordinary ambiguous-Save guard. This lets the view's
allocation avoid blocking a genuinely unaccepted creation. Ambiguous receipts
retain the ordinary review/export safeguard. Restore never rewrites the draft
JSON or auto-commits it. Subsequent user editing/Save uses the candidate owner through the normal draft safeguards. Original private files remain intact.

## Verification and physical acceptance

- Rust tests cover atomic backend protection, editable preferences, fresh-ID
  installation/idempotence, ID exhaustion, stored-item preservation, unchanged
  files, renamed/filtered/deleted/empty originals, combined schema-1 conversion,
  invalid markers and unknown-data refusal.
- Shared Flutter tests cover non-1 navigation, same-UUID working-copy switching,
  read-only information without draft resolution, verified backup ordering and
  denied/corrupt/failed same-schema migration on filesystem and Android adapters.
- `integration_test/protected_view_test.dart` uses real Rust/Flutter SQLite and
  filesystem access. It checks byte-exact sibling backups, customized view/rule/
  sort/history/settings preservation, guarded edit/delete rejection, allowed
  preferences/sorting, restart, independently backed-up pending working/recovery
  files, existing/new private drafts, pre-conversion Save receipts and unaccepted
  reserved IDs, without automatic publication.
  Windows/Fedora pipelines run the same test. The synthetic fixtures are
  reproducible through `app/test/fixtures/build_migration_fixtures.py`.

Before release, on Pixel/GrapheneOS, Samsung, Windows and Fedora:

1. Open an unchanged distributed collection and verify no conversion prompt or
   rewrite. Check built-in name/filter/delete protection and allowed sorting,
   visibility, summary settings and actual item edits.
2. Use copies of customized/deleted-default legacy files. Authorize backup access
   where required. Verify the pre-upgrade backup, restored built-in, preserved
   old views and all collection data; restart/reopen and transfer between platforms.
3. Cancel/deny backup access and simulate unavailable storage/failed publication.
   Verify the original, pending edits and exportable redacted diagnostics survive.
4. Upgrade with unpublished accepted edits, a recovery copy, and unfinished
   existing/new-item drafts. Restore explicitly, review destination confirmation,
   and verify no automatic creation, duplicate Save or cross-copy draft restore.
5. Exercise information/sidebar controls on phone and desktop, including narrow
   layouts, keyboard, enlarged text and a busy/dirty item editor.
