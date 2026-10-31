# Item drafts, Save/Cancel and recovery

Implementation candidate, 2026-10-29. Implements items 10 and 11, the second
step in the [agreed order](FEATURE_CHECKLIST.md#implementation-order).
[Owner decisions](changes-2026-10-28.md#10-editor-savecancel-controls) remain the
acceptance contract. Physical Pixel/GrapheneOS, Samsung and desktop checks are
separate from host verification.

## Shared editing behavior

Both task and folder editors use `ItemDraft`, owned by `AppController`. Opening
an editor copies its saved fields and baseline; typing or choosing tags, dates,
priority or automatic completion changes only that draft. The hierarchy, other
linked appearances and external collection do not receive those edits yet.

Save validates and atomically commits the fields and automatic-completion choice,
then closes the entire editor. Cancel discards the draft. The former Done/outer
X and inner Close-details X are gone. Desktop details and responsive dialog
editors share the same form and policy. New-item creation keeps its bottom Create
action and adds a top-right Create action in constrained layouts, as described below.

| Action | Result |
| --- | --- |
| Save / Create | Validate, commit once, close the editor |
| Cancel | Discard staged fields; keep immediate separate settings/tags |
| Outside an existing editor | Save and close if valid; otherwise keep the editor and show the error |
| Outside new-item creation | Offer Create / Discard / Keep editing |
| Back / Escape or task/view/collection switching with edits | Offer Save / Discard / Keep editing |
| Leaving without edits | No save/discard prompt |
| Background / lock / focus loss | Checkpoint the private draft; never silently commit it |
| Desktop window close / update installation | Resolve unfinished edits first; Keep editing cancels leaving |

A dialog's guarded barrier handles outside clicks before it can pop. A nested
tag/date picker or confirmation has its own route and does not commit the editor
underneath. On desktop, interactive navigation uses explicit controller guards;
unclaimed workspace taps follow the outside-click policy. A tap behind a modal
only requests closing that modal, not a navigation hidden underneath it. Escape
also works when focus has moved away from the embedded desktop editor.

The shared `EditorFormLayout` provides the former dialog's responsive behavior
for both dialogs and embedded details. At very short heights/large text, the
header, body and actions scroll together. Stable subtree keys retain focus,
selection and composing ranges while keyboard/window constraints change.

## Constrained creation actions

Item 2 is implemented in the shared Flutter form. New task/folder editors add a
top-right Create action only when available editor height is below 600 logical
pixels scaled by the controls' text size. The decision uses layout constraints
after the dialog has applied keyboard/safe-area insets, so it also works for
short desktop windows and enlarged text. Normal spacious layouts keep only the
bottom Create button; existing-item editors keep their Save control.

`EditorFormLayout.constrainedHeader` pins Cancel/Create above the scrolling
caption, fields and retained bottom action. This keeps Create accessible when
focus or scrolling reveals lower fields. Narrow/large-text controls can arrange
vertically while retaining Cancel on the left and Create on the right. If the
entire viewport is below 140 text-scaled logical pixels, the full form—including
controls—scrolls to avoid overflow. Other editors retain their existing layout.

Both Create buttons call `AppController.saveItemDraft` with the same validation,
durable Save, owner and duplicate-submission safeguards. Saving/discarding/busy
state disables both. Invalid titles or failed Saves retain the draft; a successful
Create closes the whole editor. Keyboard/window changes preserve the existing
keyed form, text controller, selection and composing range. This presentation
change performs no data migration, file rewrite on layout change or version bump.

Widget checks cover normal/short/keyboard layouts, task/folder creation,
validation/retry, busy state, retained bottom Create, very short/enlarged text,
focus/composition and existing-item Save. Native phone-layout integration uses
top Create above a simulated keyboard; desktop integration still verifies normal
creation. Physical Pixel/GrapheneOS and Samsung keyboards, landscape, enlarged
text, and short Windows/Fedora windows remain acceptance tasks before release.

## Immediate settings and separate operations

Visibility preferences still apply immediately to the current view. Creating a
tag still creates a collection tag immediately; its assignment stays in the item
draft and Cancel discards only that assignment. Those actions do not replace a
text controller or commit unfinished text.

Conversion, linking, removal and creating another item first resolve unfinished
edits. Keep editing aborts the operation. Save/Discard can resolve the fields
without closing a details editor that the following operation still needs; the
operation then uses its ordinary confirmation. Conversion refreshes the editor's
baseline and kind only after acceptance. The larger Link/Copy/global-Delete
redesign remains a later task; this work guards the currently implemented actions.

## Commit and save boundaries

Rust `item_drafts.rs` prepares a complete candidate clone and validates the
baseline editable item fields (or original creation view), graph/filter requirements and
automatic-completion constraints. `preview_item_draft` is read-only. A digest,
planned ID and source revision are retained privately before `save_item_draft`.
The latter rejects a changed revision/proposal and commits the whole candidate
once. A failed field/automatic-completion validation cannot commit only the text.

Flutter checks the working path and collection ID inside its command queue.
Copies sharing a collection UUID are not interchangeable. A changed item/view
fails safely with the user's draft retained. It is never silently merged over
newer saved values. Explicit Load latest requires consent to discard the draft.

Manual completion from the hierarchy remains an immediate action; saving an
existing item draft preserves that status instead of overwriting it with an old
checkbox value. Automatic-completion settings inside the editor remain staged.

An accepted draft uses the existing private document session and
`DocumentSaveCoordinator`; external writes still require identity, baseline,
connection, permission and read-back checks. Restoring a retained working copy
keeps its destination-confirmation barrier. Thus Save may commit locally while
the persistent file warning still requires reconnecting before publication.
Saving a draft does not mean the provider has synchronized to a cloud account.

If a Save response fails after its candidate was accepted, the semantic receipt
can recognize that result without submitting the creation twice. After a crash,
an exact committed digest clears the obsolete draft. An ambiguous creation whose
planned ID may have been consumed is retained for review/export instead of being
recreated automatically. Existing-item conflicts also retain the draft.

## Private recovery

`ItemDraftStore` uses the unchanged application support directory's `item-drafts`
folder. Files are explicitly content-bearing recovery JSON, separate from the
working SQLite collection and from privacy-filtered diagnostic logs. They retain
baseline/values, owning working path and document ID, original view and parent,
checkpoint sequence and an optional Save intent. No draft is uploaded or included
in the ordinary diagnostic export.

Checkpoints serialize and flush to a temporary file, then rename. Complete newer
temporary checkpoints are recoverable after interruption; checkpoint sequences
choose the latest complete version. Cancel/Save cleanup removes both ordinary
and temporary records. Editing and lifecycle checkpoints are locked during
cleanup so a late write cannot resurrect a cancelled draft. Reverting an edit to
its original values clears an obsolete dirty checkpoint. UI feedback distinguishes
an in-progress checkpoint from confirmed private retention and storage failure.

On restart, an Unfinished drafts offer and persistent Review drafts action allow
Restore, Discard draft, Export draft or Later. Restore does not automatically
commit. It restores the correct retained working collection with confirmation
when necessary. Unavailable/mismatched owners and changed saved items remain
protected. Unknown/unreadable draft files stay on disk and are reported, not
rewritten or deleted. A storage/cleanup failure stays visible rather than claiming
that recovery succeeded.

The `.ihtd` schema and existing collection contents need no migration for this
feature: all committed fields already exist in schema 2. The private draft format
is new. Any later conversion of an existing draft format or owner binding must
follow [migration safety](migration-safety.md), preserve original records and
account for drafts associated with old working paths. Never use a matching UUID
alone to retarget a recovered draft after a collection migration.

## Verification and remaining acceptance

Automated coverage includes atomic Rust field/completion changes, invalid and
stale candidates, matching creation constraints/receipts, private retention and
Cancel, immediate tags, navigation choices, invalid outside saves, cursor and IME
composition, route closure, temporary-file recovery, unknown versions and cleanup
races. Existing short/large-text layout checks remain applicable.

The new native `integration_test/item_draft_test.dart` exercises real Rust/Flutter
restart recovery across two collections with the same UUID, local-only Save behind
a retained binding barrier, explicit reconnection and independent external files.
Windows/Fedora native pipelines include it. Existing desktop and phone-layout
integration now use Save instead of the old autosave/Done behavior.

Before release, verify on the Pixel/GrapheneOS and Samsung, then Windows/Fedora:

1. Type in the middle of long notes, including IME composition; change tags and
   visibility, resize/rotate or open/close the keyboard. Cursor/focus must remain
   stable and linked appearances must retain the saved fields until Save.
2. Save and Cancel both tasks/folders. Check that Save closes the whole editor,
   Cancel changes no saved fields, and a newly created collection tag survives.
3. Exercise outside clicks, invalid/empty titles, Back/Escape, desktop switches,
   window close and installation preparation; Keep editing aborts leaving.
4. Resolve edits before link/removal/conversion, then confirm or cancel the
   separate operation. Immediate visibility settings must survive item Cancel.
5. Background, lock and terminate the app while editing. Restore/discard drafts
   after launch, including a draft associated with another retained collection
   or a collection copy with the same UUID. Do not overwrite another copy.
6. Interrupt Save and test full/read-only recovery storage. Retain recoverable
   text, avoid duplicate creation, preserve file connection barriers and verify
   explicit reconnection/Save-copy recovery before treating device acceptance done.

Host tests cannot prove native phone keyboard, process termination or app-upgrade
behavior. No app version/tag or production release is created by this task.

Cloud verification on 2026-10-29: static analysis, 171 Flutter tests, 77 Rust tests
and 17 Python policy/architecture tests passed. The existing desktop integration,
phone-layout integration and new restart/recovery integration passed with real
Rust/Flutter on the Linux host. An ARM64 release APK built successfully; all four
native libraries passed the 16 KB ELF check and the APK passed ZIP alignment.
Native Windows/Fedora CI and the physical acceptance above remain separate checks.

## Protected-view upgrade and draft ownership

The protected All tasks conversion can produce a new private working path.
Migration journals retain the exact source path/hash and validated candidate
path. Explicit draft Restore may follow that mapping only while its original
source hash still matches and the current document UUID/owner are unchanged.
The draft's values, baseline, original custom view and Save receipt are preserved;
Restore does not rewrite its private JSON or auto-commit. A subsequent accepted
edit uses the new owning path through normal checkpoint/Save safeguards. Original
working/recovery files and their verified backups remain available. Unrelated
same-UUID copies or changed/missing source evidence cannot authorize rebinding.
See [protected-view acceptance](protected-all-tasks.md).

A validated conversion also records the source model's digest and next ID in its
private journal (excluded from diagnostic exports). An exact pre-conversion Save
receipt can clear an obsolete recovered draft without replaying Save. A proposed
creation whose ID was still available in that immutable source can prepare a fresh
Save, even if migration allocated that ID to the new protected view. Ambiguous
creation receipts continue to require review/export; never create a duplicate to
work around an uncertain result.

## Editor appearance and section applicability

The approved [mockup](images/item-editor-approved-mockup.png) guides the full
shared task/folder form. `item_editor_style.dart` scopes pale surfaces, outlined
fields, blue controls and readable typography to this editor. It leaves other
screens' section labels/themes unchanged. A heading has a short leading rule,
a left-aligned title and a longer trailing rule; long titles wrap at large text
sizes while retaining the full accessible heading. Notes/date/priority are under
Details, followed by Tags, applicable Completion, Display and sorting, applicable
Visibility in this view, Subitems, placements and Item actions.

The title/notes controllers, draft session keys, Save/Cancel/Create handlers,
validation, separate preference actions and recovery paths are unchanged. Due
date and priority share a row only when the actual font/text scale and width fit;
otherwise they stack. Priority values retain full semantics/tooltips when the
selected field has limited width. Keyboard/short-height creation controls and
floating-label scroll clearance remain owned by EditorFormLayout.

Visibility is omitted entirely for existing leaf tasks. Existing folders retain
folder visibility/reappearance controls even without children; completed-child
and inheritance controls appear only with children. New-item visibility controls
remain unavailable until creation. Other sections contain applicable controls:
Tags still permits tag creation/selection, Subitems still permits adding children,
and display settings can configure defaults for future children. Do not hide a
section merely because the current count is zero, or leave an orphan heading.

Verification includes the four task/folder × leaf/parent combinations, heading
wrapping at 2× text, existing draft and keyboard/layout tests, plus native phone
layout and draft/restart integration. Physical acceptance remains required:

- [ ] Pixel/GrapheneOS and Samsung: compare the editor with the approved visual,
  exercise keyboard, scrolling, focus/composition and Save/Cancel/Create.
- [ ] Windows/Fedora: check narrow/wide forms, date/priority selection, large text,
  dropdown accessibility and keyboard traversal.
- [ ] Confirm all applicable settings remain reachable and empty sections absent;
  existing visibility, linking/copying/removal and conversion policies still apply.

This is shared presentation/applicability work; no schema conversion, collection
rewrite, signing identity or release version change is needed.
