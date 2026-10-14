# Document connection, saving, warnings, and recovery plan

Prepared 2026-10-14. Implements the entire "High priority: trustworthy document
connection, save status, and recovery" checklist item. This is a reviewable plan,
not a claim of physical acceptance. Implementation is available in the task
branch; automated checks and the phone-test handoff are recorded in the checklist.
Android/Pixel 9 Pro/GrapheneOS is the
first target; shared UI changes must preserve Windows/Fedora behavior.

## Outcome and boundaries

Local edits remain recoverable when the external document cannot safely be
updated. The app reports verified external saves separately from local commits.
External rename pauses publishing until explicit confirmation, even when Android
retains a working URI. External content changes require review; no automatic
merge or silent overwrite is introduced. Provider confirmation does not promise
cloud synchronization or cross-device atomicity.

## 1. Establish evidence and regression cases

- Reproduce the reported rename sequence with a disposable collection: open,
  background, rename in Files, resume, edit, reopen the renamed file, open the
  edited task. Capture external bytes before/after each operation, URI/name
  changes, local revision, and pending/recovery state without personal data.
- Inspect `app_controller.dart`, `android_documents.dart`, `MainActivity.kt`,
  `DocumentWriter.kt`, and Rust `Session` storage/recovery. Current concerns:
  filename is cached at selection; resume/poll/startup can publish; `_apply`
  derives status from private-file dirty state; pre-switch handling publishes;
  commands other than queries can cause publishing. Determine the actual
  trigger of each reported status transition rather than assuming data loss.
- Audit recovery keyed by collection `document_id`: copies can share this ID,
  so it cannot alone establish ownership of an external document's pending edits.
- Add provider fakes and controller dependency injection where needed to make
  lifecycle, publication, and switching failures reproducible without a phone.

## 2. Define and persist independent state

- Model connection state (checking, connected, rename awaiting confirmation,
  unavailable, externally changed) independently of local edits, publication
  progress, verified external revision, and recovery durability.
- Derive UI severity/messages from typed issues, not arbitrary status strings
  or Rust private-file dirty flags. Preserve unresolved issues through queries,
  editor selection, view changes, and error dismissal.
- Persist binding identity, confirmed name/hash, working-copy reference, pending
  revision, and any confirmation barrier atomically. Migrate existing active.json
  safely; restart with uncertain state must revalidate before publishing.
- Associate recovery with the selected binding and local session, not just name
  or collection ID. Keep old recoveries across switches; never assign them to a
  newly selected file solely because its name/collection ID matches.

## 3. Observe the provider and classify issues

- Add a typed native inspection operation returning current display name,
  available metadata/capabilities, read/access outcome, and content hash.
  Inspect on resume, before publication, and during existing foreground polling;
  serialize checks and writes, avoiding unnecessary repeated reads.
- Compare name and contents independently: unchanged; rename only; content
  change only; both changed. Size/time/write flags are hints, not proof. Missing
  or stale metadata must not produce invented diagnoses.
- Classify unavailable access conservatively: deletion, movement, permission
  loss, and provider outage may be indistinguishable. Do not identify a same-name
  replacement automatically. A valid URI through a move does not prove location.
- Recheck immediately before writing; retain existing content conflict and
  read-back verification. An observed revision is not an atomic provider lock.
  Do not promise detection while Android suspends IHTD in the background.

## 4. Make saving and recovery actions explicit

- Gate every publishing path, including startup, polling, background draft flush,
  mutations, retry, and pre-switch. Local commits may continue while publishing
  is blocked. Opening a task or details popup must never release the barrier.
- A rename with unchanged contents offers Confirm renamed file. Confirmation
  revalidates identity/name/hash, updates the displayed name, and explicitly
  asks to save pending edits if present. Failed validation leaves edits local.
- Unavailable access offers reconnect through the picker, retry checking, and
  Save a copy. Validate a selected destination; matching name or collection ID
  is insufficient. Show the pending source and destination before user-approved
  application of retained edits.
- External changes offer a clear comparison of available facts and safe choices:
  retain/export pending work, or explicitly reopen the external version after
  preserving local recovery. No hidden merge or unconditional overwrite.
- Permit switching after preserving pending work with explicit acknowledgement;
  cancellation/failure must retain the original binding and working copy.
  Stage and validate a new binding before replacing the active session.
- Confirm writes by reading back the intended revision. If newer edits arrive
  during a save, retain pending status until that newer revision is confirmed.
  Distinguish a private recovery-write failure from a provider-write failure;
  never promise recovery durability when it could not be verified.
- Yellow: rename/reconnection needed, unavailable access, external conflict,
  pending unpublished edits. Red: confirmed serious write/verification or local
  persistence failure; a verified write refusal can be red immediately, without
  waiting for repeated potentially damaging writes. Avoid endless auto-retries.

## 5. Build the three-level user interface

- One short clickable, persistent status banner with icon/text and yellow/red
  styling. Keep it visible at narrow widths; severity never relies on color alone.
  Saved to file appears only for the latest provider-confirmed revision.
- Popup states confirmed facts, uncertainty, external versus local save status,
  and applicable confirm/reconnect/retry/review/save-copy actions. Example:
  "Filename changed from Tasks_copy.ihtd to Tasks_copy_copy.ihtd. Contents are
  unchanged. Confirm this file to continue saving."
- Popup dismissal is not issue resolution. Popup/editor navigation has no write
  side effects. Preserve warning while edits are pending and update only when
  its underlying condition changes.
- Advanced details shows technical context and an Export diagnostic log action.
  Ensure keyboard, scrolling, large text, screen-reader labels, and desktop
  layouts work without incorporating the separate view-editor redesign.

## 6. Add privacy-preserving diagnostics

- Record bounded local events: timestamps, app/OS versions, operation/error codes,
  state transitions, revision verification outcomes, and anonymous document
  references. Cap retention/size; logging failures must not block data saving.
- Default export excludes titles, notes, collection contents, filenames/paths,
  full URIs/identifiers, and credentials. Sanitize provider exceptions before
  recording/exporting; opaque hashes/IDs must not become accidental identifiers.
- Additional diagnostics require explicit opt-in and a preview/explanation of
  included fields. Avoid collecting raw personal payloads solely to support this
  option; credentials/secrets remain excluded in every mode.
- Export a readable, versioned diagnostic file through user-selected storage.
  Export is user initiated with no automatic upload. An unavailable collection
  destination must not prevent exporting elsewhere or disturb its pending state.

## 7. Verify, document, and deliver

- State/controller/provider tests cover rename-only, rename+content changes,
  missing/moved/deleted file, permission revocation, provider outage, same-name
  replacement, write refusal, read-back mismatch, recovery failure, and repair.
- Test edits during in-flight saves/checks, lifecycle return, restart, interrupted
  metadata persistence, picker cancellation, multiple copied collections with
  the same document ID, and document switching with pending work.
- UI tests verify short messages/severity, popup actions, confirmation barriers,
  editor opening without publishing, and the latest-revision saved indicator.
  Export tests inject sensitive filenames/URIs/task data into error messages and
  confirm redaction and explicit extended-export consent.
- Run relevant Kotlin provider checks, Dart adapter/controller/widget tests,
  Flutter analysis, and Rust/storage tests when touched; run host integration
  checks to catch desktop regressions. Build and verify the ARM64 APK, signature,
  and 16 KB alignment using the existing permanent signing process.
- Physical Pixel acceptance: reproduce the original sequence and each relevant
  failure/repair case using disposable documents; inspect external contents,
  verify no silent overwrites, and test lock/background/process restart/offline
  operation. Install the candidate over the permanent-key build with a higher
  versionCode and verify retained grants, working/recovery data, and warnings.
  Record exact results; successful host checks do not replace phone validation.
- Update REQUIREMENTS.md, building/phone test instructions, and checklist as
  behavior lands. Keep stable Android publication blocked until data-safety and
  physical acceptance pass. Submit reviewable PRs into development; release
  publication is a separate step.

## Execution order and completion criteria

Work in this dependency order: evidence/tests → state and recovery ownership →
provider inspection → gated saving/reconnection → issue UI → diagnostics →
automated and physical verification. Keep intermediate commits reviewable and
do not distribute a partially implemented save-state change as a stable release.

Completion requires all high-priority checklist subitems covered, no success
message for unconfirmed external edits, no silent recovery transfer/overwrite,
verified private diagnostic exports, and recorded Pixel acceptance results.

Implementation note: extended diagnostic export includes filenames and provider
metadata after consent, but deliberately omits full document URIs even in that
mode to avoid leaking provider tokens. Recovery files from older versions are
retained; ambiguous legacy collection-ID-only recovery is not silently attached
to a different working copy. Run Flutter tests and APK builds sequentially in
one checkout: plugin registrants are shared generated files across targets.
Also avoid `--no-pub` when switching from debug/tests to release: Flutter uses
the normal build preparation to regenerate registrants without test-only plugins.
