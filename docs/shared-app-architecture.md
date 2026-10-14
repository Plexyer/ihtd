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
