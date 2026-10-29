# Shared application architecture and development workflow

Agreed 2026-10-14. General product behavior is implemented once and used by
Android, Windows and Linux. Platform adapters supply operating-system services
and observations; they do not independently define product rules or messages.

## Ownership

| Responsibility | Location |
| --- | --- |
| Task/folder graph, filters, completion and document schema | `crates/ihtd_core` |
| Shared encoding, validation, atomic filesystem operations and recovery primitives | `crates/ihtd_app` |
| Save/recovery decisions, issue state and action orchestration | Platform-neutral services under `app/lib/services/` |
| Editors, view-rule design, warning dialogs and responsive layouts | Shared widgets under `app/lib/ui/` |
| Provider/filesystem observations, access, native pickers and export destinations | Adapters under `app/lib/services/` and native platform code |
| Android URI/grant operations, insets, packaging/signing | `app/android/`, `packaging/android/` |
| Desktop filesystem identity/access and OS integration | Rust filesystem adapter and `app/windows/` / `app/linux/` as required |

Implemented boundaries: `document_save_coordinator.dart` owns save state,
barriers, recovery registry, confirmation and diagnostics; `document_adapter.dart`
defines typed references, observations, capabilities and failures.
`android_documents.dart` is a thin document-provider adapter.
`filesystem_documents.dart` uses guarded Rust operations in
`crates/ihtd_app/src/filesystem.rs` for Windows/Linux access. Only
`document_composition.dart` selects an OS adapter. The controller and warning
widgets share one flow; Rust model sessions receive private working paths.
The [cross-platform save plan](cross-platform-save-plan.md) records implementation
and acceptance scope. Physical platform acceptance remains separate.

Shared presentation: `ui/editor_dialog.dart` owns responsive form scrolling,
floating-label paint space and action reachability for view/task/folder editors.
`ui/app_theme.dart` owns header/canvas/sidebar surface roles and overlay icon
contrast. The shell paints behind safe insets and transparent system bars;
Android resource themes only supply startup colors and native contrast flags.
Keep new shared editor behavior here rather than creating per-OS dialogs.

Shared expression editing: `services/rule_draft.dart` owns draft-only slots,
stable UI node identities and a flattened display projection retaining stored
AND/OR boundaries. `ui/rule_expression.dart` renders Option-A rows or inline
runs with scoped circular pluses. `ui/rule_condition_editor.dart` supplies
focused forms and ID-bound searchable pickers. `ui/view_editor.dart` owns outer
Save/Cancel. Rust filter matching, validation, creation defaults and schema are
unchanged. Controller edit-identity/view guards run after command-queue waits;
UI drafts cannot overwrite a different working copy or a stale saved view.
See [expression plan](view-expression-editor-plan.md).

Shared removal: `crates/ihtd_core/src/removal.rs` owns actual placement counts,
revision-bound previews, cascade retention and atomic removal. Rust snapshots
supply placement metadata and deleted-container rule issues. Flutter's controller
flushes drafts and guards collection switches; `ui/item_removal.dart` owns the
common Delete confirmation. Row menus and details use the same action. Save
adapters are unchanged. Optional deleted-ID metadata retains view references
without retaining item contents; shared Flutter warns and opens rule editing.

Shared updates: `update_contract.dart`, `update_catalog.dart` and
`update_coordinator.dart` own release identity/compatibility, discovery, persisted
state and installation intent. `ui/app_updates.dart` owns shared visual feedback
and confirmation. Only `update_composition.dart` selects native adapters. Android
`UpdateBridge` provides DownloadManager, cryptographic verification and installer
access; desktop adapters currently provide explicit manual release-page handoff
until trusted package signatures are configured. Document checkpoint policy stays
in AppController/DocumentSaveCoordinator. See [update acceptance](update-acceptance.md).

Shared migrations: `services/migration_safety.dart` owns backup gates, attempt
journals, restart handling, failure logs and recovery export. Rust migration
operations inspect without mutable model open and validate separate candidates;
model sessions reject old schemas. `MigrationBackupAdapter` supplies only folder
access and create-new backups. Publication stays in DocumentSaveCoordinator.
Read [migration safety](migration-safety.md) before adding a schema or semantic
conversion; current-format UI work must not invent a migration.

Shared item drafts: `services/item_draft.dart` owns isolated fields, baselines,
private checkpoint sequencing and recovery records. AppController owns resolution,
identity guards and Save-intent handling. Rust `item_drafts.rs` validates/prepares
atomic candidates and receipts; publication remains in DocumentSaveCoordinator.
`ui/item_editor.dart` and `GuardedEditorRoute` implement one action policy across
embedded/dialog editors. `EditorFormLayout` shares responsive scrolling and stable
focus/composing subtrees with view editing. Read [item editor contracts](item-editor-drafts.md)
before adding fields or navigation; never reinstate live commits from onChanged,
dispose, keyboard/lifecycle changes or background autosave.

Shared collection settings: `crates/ihtd_core/src/settings.rs` owns collection
values and per-indicator parent/view resolution, validation and atomic updates.
Optional SQLite metadata carries these settings across platforms. Snapshots
supply complete Rust defaults; `ui/collection_settings.dart` previews staged
inheritance and uses guarded controller commands. Future metrics must use the
shared resolved settings and avoid disabled calculations; tag popularity uses
the stored count/half-life without replacing device update preferences.
See [collection settings](collection-settings.md) for compatibility and acceptance.

## Rules for future changes

1. Identify the shared product behavior first. Put domain semantics in Rust and
   interaction/presentation in common Flutter code; extend existing shared code
   rather than maintaining separate platform versions of the same feature.
2. Define a typed platform-neutral contract before adding native integration.
   Adapters report facts, capabilities and structured failure codes. Shared code
   decides severity, wording, save barriers, confirmation and recovery choices.
3. Keep platform selection in composition/bootstrap. UI and general policy must
   not import Android storage or branch on `Platform.isAndroid`/Windows/Linux.
   Native adapters can branch on their own platform details when necessary.
4. Adapt layout to available width, height, text scale, keyboard and input
   capabilities. A narrow desktop window uses the same responsive rules as a
   phone. OS-specific insets/system bars remain platform integration concerns.
5. Keep one authority for each behavior. Do not let Rust write an external file
   before a shared coordinator's barrier check, or let an adapter clear a warning
   or approve a reconnect independently. Avoid two competing save/retry loops.
6. Differences in OS capabilities are expected; unexplained differences in
   product behavior are not. Unsupported identity/rename observations must be
   represented as uncertain/unavailable, not guessed or hidden behind success.
7. Add shared behavior tests with interchangeable provider fakes, adapter contract
   tests, and appropriate native integration checks. Separate implementation
   verification from physical device acceptance in the checklist.
8. Before handoff, update requirements, architecture boundaries, tests and any
   platform limitations affected by the change. Explain a necessary platform
   exception in the PR; do not silently scope a general feature to one platform.

Example: redesign the view-rule editor once in Flutter, preserve filter semantics
in Rust, and test responsive layouts. Example: implement the save-warning dialog
once, while Android supplies document-provider access and Windows/Linux supply
filesystem access through the same observation/publication contract.

## Review checklist

- Is the product rule implemented once, with no platform-dependent UI policy?
- Do adapters only implement access, observations and capabilities?
- Are confirmations, pending edits, recovery ownership and privacy consistent?
- Does the layout depend on constraints rather than an assumed phone OS?
- Are shared contract tests and affected platform checks included?
- Are incomplete platform acceptance and unavoidable capability differences
  explicitly documented?

These rules are also linked from root `AGENTS.md`, which future coding sessions
read, and from the feature checklist and build instructions. Requirements remain
the authority for product semantics; this document defines code ownership and
the implementation/review process.
`scripts/tests/test_architecture.py` also rejects OS selection and native-adapter
imports in shared policy/controller/UI code. It complements semantic review,
rather than proving all architecture decisions automatically.
