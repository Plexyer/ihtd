# Cross-platform saving, warnings and recovery implementation plan

Prepared 2026-10-14. Planning only; no runtime migration is implemented here.
Depends on the Android save-safety work in PR #13, without requiring a stable
release first. Continue from that code and preserve its tests and recovery data.

## Goal

Use one save-state coordinator, issue model, warning popup, confirmation flow
and diagnostic-export policy across Android, Windows and Fedora/Linux. Adapters
implement access and observations. Different OS capabilities can change which
facts/actions are available, but not the safety rules or severity policy.

## 1. Map current behavior and lock down the contract

- Inventory `AndroidDocuments`, `AppController`, `DocumentStatus`, diagnostics,
  Kotlin document operations, and Rust `Session`/filesystem storage. Capture the
  current Android tests and desktop open/autosave/reload/save-copy behavior.
- Define typed `DocumentReference`, `DocumentObservation`, `DocumentCapabilities`,
  `DocumentFailure` and `SaveState`. Keep OS handles/paths/URIs out of UI policy.
  Observation includes confirmed identity when available, name, content hash,
  access outcome and optional size/time/capabilities, with identity confidence.
- Specify one adapter contract for pick/open/create, inspect/read, guarded
  publish/read-back verification, and diagnostic/export destination selection.
  Adapter publication returns the exact confirmed revision/hash or typed failure.
- Adopt the agreed safety policy everywhere: rename confirmation; no silent
  conflict overwrite or pending-edit transfer; yellow actionable warnings; red
  confirmed persistence failures; success only for the latest external revision.
  Document the intentional desktop change from silent external reload to the
  same explicit external-change/reopen flow as Android. Keep unrelated domain
  behavior and file format unchanged.

## 2. Establish a shared publication boundary

- Introduce `app/lib/services/document_adapter.dart` and
  `document_save_coordinator.dart` (proposed names). Extract state transitions,
  pending/confirmed revision tracking, persisted barriers and recovery ownership
  from `android_documents.dart` into the coordinator.
- Keep Dart responsible for shared interaction/safety decisions and Rust for
  domain validation, encoding, private commits and filesystem primitives. Use
  typed JSON command outcomes if necessary; do not parse exception text to
  infer file states. Regenerate bridge bindings only if the public API changes.
- Use private working copies for desktop as well as Android, so accepted edits
  can remain local while the external destination is blocked. External desktop
  paths remain direct-edit destinations, not an import/export-only workflow.
- Route every external write through the coordinator: mutation saves, startup,
  retry, background draft flush, Save a copy and switching. Refactor Rust's
  desktop direct-publication path before enabling shared barriers; wrapping its
  existing autosave with a new popup would otherwise be insufficient.
- Ensure no competing publisher exists. Serialize session operations; distinguish
  private durability, external verification and new edits during an in-flight
  save. Preserve atomic desktop replacement and provider conflict checks.

## 3. Reduce Android to an adapter and migrate its data safely

- Move provider-specific access to a thin Android adapter backed by the existing
  Kotlin channel. It supplies URI/grant operations, observations and failure
  codes, without messages, severity, confirmation or recovery-selection policy.
- Migrate active.json and archived binding metadata into a versioned shared
  session registry. Preserve private paths, baseline hashes, pending revisions,
  unresolved barriers and all old recoveries. Migration is atomic and resumable;
  no old files are deleted merely because their format changed.
- Do not adopt ambiguous legacy recovery by collection ID alone. Validate binding
  ownership; restart and APK update must not release pending-save barriers.
- Run the original Android adapter/controller/dialog regressions against the new
  coordinator so extraction does not weaken the implemented protections.

## 4. Implement the desktop filesystem adapter

- Reuse Rust encoding/atomic publication and expose structured filesystem
  observations and guarded writes to the shared coordinator. Handle native
  open/save pickers, startup document paths, Save a copy and exports identically
  to their existing user entry points.
- Investigate Unix device/inode and Windows file IDs for replacement detection;
  expose uncertainty for mounts/sync providers that do not offer stable identity.
  A path, filename, timestamp or collection ID alone is not proof of identity.
- Detect content changes with hashes even when size/time are unchanged. Treat a
  missing original path conservatively; finding a rename may be unavailable and
  require picker-based reconnection. Never scan broad user directories to guess
  the new destination or silently create a new file at the old path.
- Check replacement, permissions, removed mounts, read-only files, disk-full,
  write and verification failures. Revalidate before atomic replacement; explain
  the remaining cross-device race rather than promising an atomic provider lock.
- Persist and restore desktop bindings/private recoveries without changing the
  Windows support-directory identity or deleting user files on uninstall.

## 5. Make UI and diagnostics truly platform-neutral

- Change `AppController` to depend on the coordinator, injected at bootstrap with
  Android or desktop adapters. Remove separate Android/desktop policy branches
  while retaining native picker/integration implementations underneath.
- Make `DocumentStatus` and `DocumentIssueDialog` read only shared save/issue
  state and actions. Remove imports/references to AndroidDocuments; render the
  same three levels of information and persistent issue behavior on all systems.
- Expose actions from state/capabilities, not OS names. Keep the common responsive
  dialog/editor layout for narrow windows, phones, keyboard and large text.
- Share bounded event logging, allowlisted error codes, anonymous document
  references and explicit export consent. Adapters supply safe app/OS versions
  and native export destinations. Default logs exclude personal contents,
  names/paths/identifiers and raw errors; extended export still excludes secrets.

## 6. Verify parity and deliver

- Run the same coordinator contract scenarios against Android and filesystem
  fakes: rename-only, rename+content changes, same-name replacement, lost access,
  denied/partial writes, confirmation cancellation, restored access, stale
  approvals, in-flight edits, document switches and recovery ownership.
- Add real temporary-filesystem tests on Linux and native Windows for identity,
  replacement, atomic saves and recovery. Keep provider-native Kotlin checks.
- Exercise shared popup/actions/redaction on desktop and narrow/large-text
  layouts. Verify there is no external write on editor/popup opening or dismissal.
- Test migration/restart with legacy Android bindings and retained pending edits,
  desktop startup paths, failed private persistence and interrupted metadata
  writes. Ensure failed migration leaves old data recoverable.
- Run Rust tests, Dart analysis/all tests, host UI checks and native Windows CI;
  build candidates for all affected platforms. Build Flutter targets sequentially
  in one checkout to avoid shared generated-plugin conflicts.
- Physical acceptance remains owner work on the Pixel, Windows PC and Fedora
  laptop, including the chosen mounted/sync provider. Record test coverage and
  limitations; do not mark physical acceptance from host tests alone.
- Update requirements/checklist/build instructions to the actual shared behavior,
  open reviewable PRs into development, and leave stable publication separate.

## 7. Document and enforce the development workflow

Documentation is part of this plan, not a later memory-only instruction:

| File | Purpose |
| --- | --- |
| `AGENTS.md` | Mandatory shared-first rule and architecture link for future coding sessions; required pre-change reading and handoff checks. |
| `docs/shared-app-architecture.md` | Authoritative layer ownership, adapter boundaries, responsive-layout rules, examples and review checklist. |
| `REQUIREMENTS.md` | Shared product semantics and explicitly justified platform capability differences; update as the migration lands. |
| `docs/FEATURE_CHECKLIST.md` | Track the migration, verification and physical acceptance; prevent Android-only completion being mistaken for platform parity. |
| `docs/building.md` | Links and commands for shared tests plus native adapter checks; describe what each check proves. |
| `docs/cross-platform-save-plan.md` | Execution order and acceptance criteria for this migration. |

The architecture policy and AGENTS links are documented now; runtime behavior,
test-command additions and completed migration markers are updated only when the
corresponding implementation actually lands. A future general feature starts in
shared code; any platform exception must be explained and reviewed explicitly.

## Completion criteria and priority

Implement the contract/publication boundary first, then migrate Android and add
desktop access, then wire the common UI/diagnostics and verify all platforms.
The boundary comes first because desktop currently writes before a coordinator
could stop it. Work through small coherent commits with regression checks.

Done means one authority for save decisions, no platform checks in the warning
UI, the same safety decisions in all adapter contract tests, no recovery loss
through migration, and recorded native/physical acceptance. Broader design work
such as the view-rule redesign then follows the documented shared-first workflow.
