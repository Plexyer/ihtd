# View-expression editor physical acceptance

Created 2026-10-14. Shared implementation and host/native automated checks are
separate from these physical-device tests. Use disposable collections/views.
Record the platform, app version/build, outcomes and any screenshots below.
The [implementation plan](view-expression-editor-plan.md) records the design,
shared ownership, compatibility constraints and automated evidence.

## Candidate and preparation

Current verified Android candidate:
`/workspace/ihtd/dist/view-expression-editor/IHTD-0.2.2-build11-android-arm64-test.apk`
(0.2.2 build 11, runtime commit `e28226e`). SHA-256:
`5c9a5f0502863938246ab5866087e143be8cdb03d48b2328ef666962a74311ec`.
Permanent certificate and ELF/ZIP 16 KB checks pass. Use this build or a newer
candidate containing the same feature. Install a permanently
signed Android candidate over the existing permanently signed IHTD installation
to retain its data/grants. Windows/Fedora candidates must be built from the
same feature commit using normal packaging workflows; the cloud host's Linux
tests are not physical Windows/Fedora acceptance. Keep an independent copy of
the test `.ihtd` file before editing existing views.

Create a Japan trip folder with task children, a Packing tag, Low/Medium/High
priorities and dates before/after 2026-10-31. Include one shared task and two
containers named Trip to check identity selection. Include a task's notes with
the literal `Invoice 123` and differently cased text.

## 1. Start and edit an expression

- [ ] Create a view; choose AND through the empty circular plus. Two unfilled
  slots appear, connected by AND. Save with an empty slot: no view is committed
  and the message identifies unfinished conditions.
- [ ] Fill left with Title contains Japan. Fill right with an OR group, then
  configure Due before 2026-10-31 and Due after 2026-12-01.
- [ ] The overview reads `Title contains Japan AND (Due before … OR Due after …)`.
  It contains compact summaries rather than expanded nested rule forms.
- [ ] Tap a condition, change it and use form Cancel: its original summary
  remains. Use Done: only the local view draft changes. Outer Cancel discards
  the expression draft; outer Save view commits it.

## 2. Addition scope and operator changes

- [ ] Use the inner plus before `)` to add a Packing tag alternative. It adds
  OR inside that group; it does not extend the outer AND chain.
- [ ] Use the outer plus after `)` to add Priority at least Medium. It adds an
  AND condition outside the OR parentheses.
- [ ] Add another AND group to the AND chain and fill it: one continuous AND
  chain is shown. Repeat with OR inside OR. Different operators retain brackets.
- [ ] Select a connector and change AND/OR: operand values are preserved, and
  the change applies to the displayed chain. Cancel the operator picker: no change.
- [ ] In a condition's actions choose Combine with another condition; select
  OR and fill the new slot. Only that chosen expression is wrapped.
- [ ] Remove first/middle/last operands and a complete group. Surviving values
  retain their scope/order. Removing all draft operands leaves an empty slot,
  never an implicit All items. Explicit All items remains available.
- [ ] Test nested Exactly one and NOT: their boundaries remain; two matching
  branches in an Exactly one group exclude the item. Repeated branches are not
  silently deduplicated. Opening and saving an existing rule does not rewrite it.

## 3. Every condition and reference repair

- [ ] Title and Notes: all six comparisons, numeric text, case sensitivity.
  Type new text and immediately toggle Case sensitive: new text remains.
- [ ] Tags: search/select; create a tag from its form. The separate collection
  save is explained; cancelling a view does not remove the created tag.
- [ ] Containers: select a task or folder by the picker ID; duplicate Trip names
  remain distinguishable. Direct children and all descendants produce different
  matches; the container itself is excluded.
- [ ] Dates: before/on/after/on-or-before/on-or-after, Has date and No date.
  Presence rules show no calendar/date value. Switching comparisons keeps the
  most recently chosen date where applicable.
- [ ] Priority: Is/At least/At most and None/Low/Medium/High; item type and task
  completion; explicit All items. Saved summaries display each selected option.
- [ ] Delete a referenced container in a disposable view. Its yellow tile and
  hierarchy warning open the editor, where the missing container is highlighted.
  Replace it using the picker or remove its rule, then Save: warning clears.

## 4. Compatibility, saving and safeguards

- [ ] Open an existing complex saved view and change only its name. Matching,
  suggested values when adding tasks, shared placements and view preferences
  remain the same. Save/reopen the collection and repeat the check.
- [ ] Create a task through a tag-based view; suggested tags remain correct and
  the complete filter is checked before accepting the task. Test nested tag
  OR and Exactly one rules, not only a simple tag predicate.
- [ ] Cancel editing: no view mutation/save occurs. Failed view validation keeps
  the draft open with a useful message. Last remaining view cannot be deleted;
  deleting another view requires confirmation and leaves tasks/links intact.
- [ ] Rename/disconnect the external file, then save a view edit: existing shared
  yellow/pending/recovery behavior remains. Reconnect explicitly and reopen the
  file; the saved expression is correct. See shared-saving acceptance for details.
- [ ] If testing programmatic/stale edits, switch working copies or change the
  saved view while the editor is open. Save rejects the stale destination/rules,
  including a separate copy with the same document UUID.

## 5. Layout and inputs

- [ ] Pixel/GrapheneOS portrait: each AND/OR starts its following operand row;
  parentheses and indentation make mixed scopes visible. Inner/outer pluses are
  easy to distinguish, and Save/Cancel remain reachable.
- [ ] Keyboard open/closed, large text (including 2x), landscape and long names:
  no clipping/overflow or inaccessible actions. Long text can be read and edited.
- [ ] Resize/reorient while typing: focus, text selection and draft values survive.
  Deep groups remain editable without a new nesting limit or horizontal scrolling.
- [ ] Windows/Fedora: inline expressions use wider space, wrap readably as needed
  and become Option-A rows in narrow windows. Verify keyboard focus/activation,
  operator actions, plus tooltips and mouse use.
- [ ] Screen-reader/keyboard checks: plus controls identify their chain scope;
  condition editing, removal and parentheses/negation are understandable without
  relying on color alone. Destructive view actions are separate from Save/Cancel.

## Results

| Platform | Build/commit | Outcome/evidence |
| --- | --- | --- |
| Pixel 9 Pro / GrapheneOS | Pending owner test | Physical acceptance pending |
| Windows | Pending native candidate/owner test | Physical acceptance pending |
| Fedora | Pending native candidate/owner test | Physical acceptance pending |
