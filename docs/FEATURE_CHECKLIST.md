# Feature checklist

Updated 2026-10-31 with implementation evidence for the owner's clarified backlog.
The section below and the existing agreed-work sections contain approved
requirements. Optional suggestions still require discussion. Implementation and validation evidence are tracked separately; an approved
requirement is not automatically complete. The migration foundation below is an
implementation candidate; physical acceptance remains open.

## Approved follow-up: sorting labels, hidden children and editor polish

Agreed 2026-10-31 after the owner's v0.3.0 phone test. These tasks are specified
and **not implemented**. The owner will review this checklist and separately
approve starting the first task. Implement general behavior/UI once for Android,
Windows and Fedora; preserve existing data, drafts and save/recovery safeguards.

1. [ ] **Rename sorting Title to Alphabetic.** Use “Alphabetic” consistently in
   user-facing sorting options/descriptions. Preserve the existing sorting
   algorithm, ascending/descending behavior, stored values and preferences.
2. [ ] **Explain children hidden by view rules.**
   - Keep the existing filtered Total/completed-total semantics. Add a compact
     hidden-items icon plus count for direct child tasks excluded by the view's
     rules; distinguish rule exclusion from the Unfinished/Completed tab and
     other visibility settings. Do not count deeper descendants in this summary.
   - Show it whenever such hidden children exist, even if Total is disabled;
     omit it at zero. Provide an accessible label explaining the icon/count.
   - Keep the established centered title, bottom footer with Total followed by
     next date, and priority stack centered against the whole card including
     its footer. Use footer space carefully, minimize displacement and avoid
     clipping/overflow on narrow layouts or enlarged text.
   - Tapping the indicator opens an explanation such as “3 direct children
     hidden by view rules” and offers to open this parent in All tasks. Preserve
     existing unfinished-draft navigation safeguards and protected-view identity.
     Do not silently change the current view's rules or counting semantics.
3. [ ] **Restyle the full task/folder editor to the approved mockup.**
   - Adopt its overall visual treatment: spacing, fields, switches and section
     dividers, while retaining every existing applicable function and setting.
   - Section titles interrupt a thin horizontal line near the left edge: a short
     leading rule, title, then a longer rule extending across the remaining width.
   - Preserve Save/Cancel, validation, draft/recovery behavior, independent
     operations and responsive keyboard/short-window controls. Adapt the design
     to available space on phone and desktop; retain readable labels and touch
     targets. Hierarchy card restyling is outside this editor task.
   - The mockup is a styling reference, not a replacement functional specification:
     its illustrative field values and helper copy do not override agreed behavior.
4. [ ] **Hide empty settings sections.** For both tasks and folders, render a
   section's heading/divider/spacing only when it contains applicable controls.
   In particular, omit the empty “Visibility in this view” section on leaf tasks.
   A childless folder may still have valid folder-visibility controls: retain
   sections with applicable controls rather than hiding all sections on leaf items.

Approved visual reference: [task/folder editor mockup](images/item-editor-approved-mockup.png).
Task 3 supplies the section styling used by task 4; implement and verify those
coherently. Other existing checklist items and physical acceptance remain open.

## Owner-clarified Changes.docx backlog

Source: all 12 requests and 13 screenshots in Changes.docx, plus the owner's
subsequent selectable answers and corrections through 2026-10-28. The complete
[clarified specification](changes-2026-10-28.md) preserves the original numbering,
priorities, examples and later linking/copying rework. Implementation status is
recorded on each item below. Keep general logic/UI shared across Android, Windows and Fedora.
Ask the owner about genuinely unresolved behavior rather than inventing defaults.

### Implementation order

Agreed 2026-10-28. Numbers in parentheses refer to the specification's original
feature numbers, not new priorities. Use this order when planning implementation:

1. **Migration safety foundation:** verified backups, staged migration,
   recovery and automatic failure diagnostics before converting existing data.
2. **Editor drafts and Save/Cancel (11 + 10):** implement together, including
   stable cursor behavior, cancellation, exit prompts and draft recovery.
3. **Collection settings and default inheritance (7):** provide the settings
   needed by indicators and tag suggestions.
4. **Linking/copying/removal and Links counter (13 + 3):** first appearance
   counting and copy primitives, then global Delete, blocked-Unlink replacement
   and the Link/Copy dialogs.
5. **Sorting and drag insertion (4):** shared manual order and per-view automatic
   sorting against the clarified hierarchy behavior.
6. **Priority icons (8):** prepare the shared designs needed by indicators.
7. **Summary indicators (5):** build on settings, inheritance and priority icons.
8. **Tag picker and popularity (6):** build on collection settings and committed
   item drafts.
9. **Protected All tasks view (1):** include preservation of existing customized
   views during migration.
10. **Additional Create button (2):** integrate with the settled editor behavior.
11. **Branding and update-indicator placement (9 + 12):** coordinate header changes
    and platform icon/splash assets.
12. **Full upgrade and device testing:** verify upgrades, data preservation,
    recovery and changed features on Pixel/GrapheneOS, Samsung, Windows and Fedora
    before release.

Steps 6, 9 and 11 are mostly independent and may be brought forward. Migration
and preservation tests accompany every data-changing step; do not defer them
until step 12. This order is a plan, not completed implementation.

### Full upgrade acceptance — step 12

Candidate **0.3.0+15**, baseline **v0.2.5+14**. Feature implementation candidates
are in place; release readiness still requires the physical results below.
Follow [upgrade instructions](upgrade-acceptance.md) and record each platform in
[the result sheet](upgrade-acceptance-results.md).

- [x] Generate synthetic intact/customized/deleted-default/pending fixtures using
  the actual pinned v0.2.5 model/storage, with old-reader checks and provenance.
- [x] Compare every released document field with the upgraded projection; verify
  backups and exactly the protected-view conversion, with no unrelated changes.
- [x] Combine feature edits/settings/copying, disconnected file saves, private
  draft restart/restore and safe update preparation in a native acceptance test.
- [x] Add checksum-pinned actual v0.2.5 Windows EXE/Fedora RPM upgrade, uninstall,
  reinstall and data-retention verification to disposable native CI.
- [x] Package synthetic test data, provenance and instructions as a separate CI
  artifact and version-tag release asset; keep production signing/tag gates.
- [ ] Review successful three-platform candidate CI and merge the release PR.
- [ ] Create the reviewed master tag; verify the permanently signed APK and
  complete release assets. Publish as a prerelease for direct testing first.
- [ ] Test in-place upgrade, migrations, backups/refusal/failure diagnostics,
  existing data/recovery and combined features on Pixel/GrapheneOS and Samsung.
- [ ] Test Windows 11 Explorer/installer and Fedora Wayland/scaling/file picker/
  rclone on physical machines, recording exact OS and package identities.
- [ ] Record issues/retests and approve stable promotion of the exact tested
  assets. New updater end-to-end checks need a genuinely later stable version;
  prereleases remain excluded from discovery.

### Implementation and acceptance tasks

- [ ] **Migration safety prerequisite — before migrating existing data.**
  - [x] Determine whether a migration is actually required, including semantic
    transformations that change existing data without changing a schema number.
  - [x] Before migration, create a consistent, durable backup beside the original
    collection file, or in an authorized backup folder where necessary. Verify
    it by reading it back before changing data; do not overwrite earlier backups.
  - [x] On Android, acquire any missing backup-folder authorization first. With
    no usable destination, insufficient space or failed verification, stop the
    migration and preserve existing data; do not silently fall back to a private
    collection backup instead of the location the owner chose.
  - [x] Migrate a separate candidate, validate preserved contents/relationships
    and new metadata, then publish through the shared identity/conflict/read-back
    safeguards. Preserve pending working copies and recoveries independently.
  - [x] On failure/interruption, stop further writes, retain the backup/recoverable
    state and automatically persist a privacy-preserving diagnostic log. Provide
    clear failure/recovery information and user-initiated log export; never upload
    logs automatically or include collection contents/credentials by default.
  - [ ] Verify backup refusal/failure, staged migration failure, publication
    failure, interruption/retry, external changes and successful upgrades from
    the currently distributed version before releasing data-migrating features.
  Implementation candidate: [migration safety and acceptance](migration-safety.md).
  Shared policy, Rust conversion, native backup adapters and host verification are
  implemented; the parent stays open for physical acceptance. Schema-2 files with
  an intact original All tasks view need no migration; customized/missing
  originals use the protected-view semantic plan. Future conversions must
  register their own plan and preservation checks before shipping.
  See [migration safety requirements](changes-2026-10-28.md#14-migration-safety-prerequisite).
- [ ] **1 — Medium: protect All tasks.**
  - [x] Protect its name, unfiltered rule and deletion in shared Rust and UI;
    keep sorting, visibility/display preferences and item editing available.
  - [x] Infer an intact original view without rewriting the file. For renamed,
    filtered or missing originals, add a fresh protected view through the verified
    backup/candidate gate, preserving every old view and all other collection data.
  - [x] Keep pending working/recovery files and unfinished private drafts safe;
    use validated migration-owner evidence rather than UUID-only draft rebinding.
  - [ ] Verify physical upgrades, authorization/refusal and recovery on Pixel /
    GrapheneOS, Samsung, Windows and Fedora before release.
  Shared candidate: [protected-view behavior and acceptance](protected-all-tasks.md).
  No app version bump; schema-2 semantic conversion is explicit, not a loader repair.
- [ ] **2 — Medium: additional top-right Create action.**
  - [x] Show it for new tasks/folders in short or keyboard-constrained layouts
    on every platform; keep normal layouts unchanged and retain bottom Create.
  - [x] Use the same draft validation/Save and busy guards for both actions;
    preserve typed text, focus and composition through keyboard/window changes.
  - [x] Keep top controls visible while the short form scrolls; adapt narrow/
    enlarged-text controls and retain the fully scrolling extreme-height fallback.
  - [ ] Verify physical phone keyboards, landscape/enlarged text and short
    desktop windows on Pixel/GrapheneOS, Samsung, Windows and Fedora.
  Shared candidate: [constrained creation actions](item-editor-drafts.md#constrained-creation-actions).
  Presentation-only; no data conversion, schema or app-version change.
- [ ] **3 — Medium: show linked appearances.**
  - [x] Display compact `Links: N` below the row menu only for N >= 2, counting
    all collection hierarchy paths, including those through linked parents.
  - [ ] Verify counters/layout on physical phones and desktop upgrades.
  Shared candidate: [link/copy/removal behavior and acceptance](link-copy-removal.md).
- [ ] **4 — Medium: per-view sorting and clear drag insertion targets.**
  - [x] Offer Manual, Title, Due date and Priority for every parent and the top
    level. Automatic modes support ascending/descending; modes are per view.
  - [x] Keep one shared manual order. A between-sibling drop while automatically
    sorted switches that parent/current view to Manual, uses the displayed order
    as its starting point, applies the drop and saves the shared manual order.
  - [x] In automatic sorts, keep folders first and sort each kind separately.
    Undated and None-priority items stay last in either direction. Break ties by
    title, then manual order for identical titles.
  - [x] Show between-item insertion indicators as well as inside-parent targets.
  - [x] Preserve hidden siblings' manual slots during filtered reordering.
  - [x] Block moving a child out of a shared parent, including inherited sharing;
    explain that an independent copy is needed first. Allow shared reordering.
  - [ ] Verify upgrades, physical phone gestures/layout, native desktop behavior
    and cross-platform collection transfer.
  Shared candidate: [sorting, drag insertion and acceptance](sorting-drag-insertion.md).
  Optional metadata needs no schema-2 conversion or rewrite on open. Host tests
  and native Linux integration pass; physical acceptance keeps the parent open.
- [ ] **5 — Medium: compact direct-child summary indicators.**
  - [x] Default Total and High-priority count on; Low/Medium counts and next due
    date off. Allow an optional ratio replacing the plain count: `Total: 2 / 5`.
  - [x] Count direct child tasks only, included by the view rules/current tab.
    The ratio is the exception: include both completion states matching the view
    rules regardless of tab. Next due means earliest date today or later.
  - [x] Put Total (including zero) and Next date on one bottom footer line,
    Total first. Show enabled priority icon/count pairs only for nonzero counts;
    vertically center the remaining one/two/three-pair stack in the card.
  - [x] Match the approved mockup: title/metadata and ordinary controls center
    within the main body; priority stacks center across the full card including
    its footer. Preserve these alignments with enlarged text.
  - [x] Inherit each indicator independently: collection defaults, optional
    parent defaults, then parent/view overrides. Only non-overridden settings
    follow later default changes. Skip disabled indicators' metric computation.
  - [x] Hide next date when none qualifies; show summaries only on tasks or
    folders currently having children. Empty folders and leaf tasks show none.
  - [ ] Verify physical phone/desktop layouts, accessibility, date rollover,
    provider recovery, upgrades and cross-platform transfer.
  Shared candidate: [summary calculation, layout and acceptance](summary-indicators.md).
  Queries are read-only derived data; no stored-data conversion is needed.
- [ ] **6 — Medium: clear selected tags and a bounded suggestion list.**
  - [x] Show all selected tags above a light divider; below show up to N popular
    unselected tags plus Select other. N defaults to 5 and is a collection setting.
  - [x] Select other opens searchable multi-select with Done/Cancel; Done applies
    to the item draft and picker Cancel discards the picker operation.
  - [x] Rank committed manual assignments by gradually decaying usage, excluding
    automatic/copied assignments. Influence halves after 3 days by default;
    configure that period in collection settings. Older collections start without
    usage scores and use alphabetical suggestions until usage establishes rank.
  - [ ] Verify physical phone/native desktop search, selection/cancellation,
    popularity, keyboard/layout and upgrade/transfer/recovery behavior.
  Shared candidate: [tag selection, ranking and acceptance](tag-selection.md).
  Optional history requires no conversion of existing assignments or schema-2
  files. Read-only rank/open checks retain existing bytes and private drafts.
- [ ] **7 — Medium: collection Settings page.**
  - [x] Add Settings to the top-right menu, with isolated Save/Cancel and validated
    tag suggestion count (default 5) and fading half-life (default 3 days).
  - [x] Store collection indicator defaults, optional shared defaults per parent
    and independent parent/view overrides. Allow each field to resume inheritance.
  - [x] Provide shared controls, reject stale/different-collection saves, preserve
    existing visibility and document-save safeguards, and verify old-file retention.
  - [ ] Verify physical upgrades, keyboard/layout behavior and cross-platform
    collection transfer on Pixel/GrapheneOS, Samsung, Windows and Fedora.
  Implementation candidate: [collection settings and acceptance](collection-settings.md).
  Optional metadata needs no conversion of existing schema-2 data; loading defaults
  does not rewrite files. Summary metrics and tag-picker/popularity behavior remain
  in items 5/6; these settings provide their shared foundation.
- [ ] **8 — Medium: consistent priority icons.** None: no icon; Low: gray `!`;
  Medium: soft yellow leaning orange; High: red rounded-triangle outline with
  red `!`. Use the same designs at smaller sizes in the summary counters.
  - [x] Replace row flags with a reusable shared icon and use the same designs
    in item/view-rule priority selectors, retaining accessible labels/tooltips.
    Provide an explicit size for the upcoming compact counters.
  - [ ] Verify physical-device legibility, large text and accessibility across
    Pixel/GrapheneOS, Samsung, Windows and Fedora.
  Shared candidate: [priority icon design and acceptance](priority-icons.md).
  This is presentation-only and needs no stored-data migration. Summary counter
  integration remains in item 5.
- [ ] **9 — Medium: new branding across platforms.**
  - [x] Implement the sketch's filled blue diagonal infinity-like shape with a
    white tick in each lobe; use one canonical vector and generated platform assets.
  - [x] Replace shared header/About branding, Windows runner/installer ICO,
    Fedora SVG/portable window icon and Android density/adaptive/themed icons.
  - [x] Replace native Android splash and add shared branded initialization on
    all platforms, as the owner selected, with no added minimum display delay.
  - [ ] Verify physical installed icons, startup, accessibility and in-place
    upgrades on Pixel/GrapheneOS, Samsung, Windows and Fedora.
  Shared candidate: [branding, startup and acceptance](branding.md).
- [x] **10 — High: coherent editor Save/Cancel controls.** Replace Done with
  top-right Save, add top-left Cancel, and remove both confusing X controls.
  Save closes the editor; never leave its empty outer window open.
- [ ] **11 — High: cancellable item drafts and stable text editing.**
  - [x] Fix the reported note-cursor jump; stage title/notes/tags/due date/priority
    and automatic completion until Save or a valid existing-editor outside tap.
    Cancel discards the draft. Apply the same policy to task and folder editors.
  - [x] With unsaved changes, Back/Escape and desktop item/view/collection
    switches prompt Save/Discard/Keep editing. New-item outside taps prompt
    Create/Discard/Keep editing. Invalid existing-editor outside saves stay open.
  - [x] Retain unfinished drafts separately and offer restore/discard after an
    app close/crash. Keep external document save/recovery barriers intact.
  - [x] Apply visibility settings immediately. Newly created collection tags
    survive item Cancel, but cancelled assignments do not. Conversion and
    Link/Unlink/Delete are separate operations after resolving unfinished edits.
  Shared implementation: [item draft behavior and acceptance](item-editor-drafts.md).
  Controls, atomic Save, private recovery, cursor/composition retention and action
  guards are implemented. Item 11 remains open for physical device/upgrade
  acceptance; host checks do not establish that result. The collection format
  stays schema 2 and needs no data migration for these editor changes.
- [ ] **12 — Low: move the update indicator.**
  - [x] Put every state immediately left of the top-right three-dot menu.
    Reserve a 48px slot while hidden so the brand, filename and menu do not shift.
    Reuse existing animations, reduced motion and download/install safeguards.
  - [ ] Verify physical layouts and update transitions on all target platforms.
  Shared candidate: [branding and header acceptance](branding.md).
- [ ] **Additional approved work — revise Unlink/Delete and add Link/Copy.**
  - [x] Two or more appearances: offer both Unlink and Delete; one appearance:
    Delete only. Delete removes the item everywhere and always confirms. For
    multiple appearances, explain the global effect and direct users to Unlink
    for local removal. Preserve children that have surviving appearances elsewhere.
  - [x] Keep linked parents' children shared. Block a child Unlink that would
    affect other parent appearances; identify the blocking linked parent and
    offer Cancel or replacement of the selected parent occurrence with a full,
    independent copy. Then delete the selected copied child/descendants, leaving
    originals elsewhere untouched. Force full depth/every appearance independent
    for this special operation; do not leave the removed copied branch at top level.
  - [x] Add a searchable Link/Copy destination popup for tasks/folders/Top level.
    Default to Link, with copy depth disabled. Bottom actions: Cancel and a single
    mode-dependent Link to/Copy to. Info expands the popup with two explanations.
  - [x] Copy defaults to source only, linking its children. Offer available
    depths and All descendants. By default copy each unique item once, preserving
    internal links; an unchecked Make every appearance independent option disables
    reuse when checked. Deeper references reuse an item copied within the depth.
  - [x] Exclude self/descendants in Link mode. Copying into self/descendants is
    allowed only with All descendants: automatically select/lock that depth and
    show an explanation. Preserve acyclicity and original identities elsewhere.

  - [ ] Complete physical upgrade, keyboard/layout and graph-action acceptance
    on Pixel/GrapheneOS, Samsung, Windows and Fedora.
  Implementation candidate: [shared actions and acceptance](link-copy-removal.md).
  No automatic graph/schema conversion is needed. Host verification is separate
  from the remaining device/provider checks.

Dependencies: migration safety before any feature that converts existing stored
data; 7 before 6; 8 before 5; collection/default support from 7 also
supports 5; 10 and 11 together. Coordinate 3 with the revised linking/removal
contract. Earlier intermediate choices permitting different child lists for two
linked appearances, and the old three-button Link/Copy design, were superseded.

Checked subitems record implemented scope; physical acceptance remains separately
open. See the specification for the exact editor action matrix and copy examples.

## Remaining agreed work

- [x] Allow moving a task/folder into its own descendant by promoting its direct
  children to the dragged placement's former parent/top level, preserving their
  subtrees and shared IDs. Verify ordering, completion and phone drag acceptance.
- [ ] Fedora: build, test, and provide a runnable Linux package; verify on laptop.
  - [x] Prepare Fedora RPM and portable-bundle build definitions.
  - [x] Unblock the Linux build environment (Fedora 44 under updated WSL).
  - [x] Pass 47 Rust tests, Flutter analysis, and Linux UI integration test.
  - [x] Build RPM/portable packages and verify installed release launch.
  - [ ] Verify on the laptop: file picker, Wayland/scaling, and rclone mount.
- [ ] Android: Google Pixel 9 Pro running GrapheneOS is the first phone target.
  - [ ] Confirm the phone's installed Android version (minimum API 35/Android 15).
  - [x] Choose direct editing through Android's Storage Access Framework (SAF)
    with private working copies and local recovery.
  - [x] Build an ARM64 APK with the shared Rust model and bundled SQLite.
  - [x] Verify native libraries and APK packaging support 16 KB page sizes.
  - [x] Implement collection creation, reopening, save-copy and export on Android;
    never pass a `content://` URI to Rust as a filesystem path.
  - [ ] Verify those document actions through Files on the actual phone.
  - [ ] Preserve pending edits and recovery copies across backgrounding, screen
    lock and process restart; exercise failed saves and revoked file access.
  - [ ] Adapt touch scrolling, dragging, keyboard/insets, back navigation and
    narrow-screen editors, including large text and portrait/landscape.
  - [x] Pass Flutter analysis, six document-adapter tests, five native provider
    checks, 47 Rust tests and both host UI integration tests.
  - [ ] Verify installation, launch and document round trips on the actual Pixel
    with GrapheneOS default settings.
  - [ ] Verify core operation without Google Play services or network access;
    use scoped document grants rather than broad storage permissions.
  - [ ] Define durable release signing and test an APK update preserving data.
    Development-signed APKs must be clearly labelled as test builds.
  - [x] Document installation, file transfer/backup and any remaining limitations.
  - [ ] Follow up with automatic external-provider reload; the first milestone
    reports external changes and requires reopening or saving a separate copy.
- [ ] Design refinement after using the prototype, as originally planned.
  These are areas to review together, not a requirement to redesign everything.
  - [ ] Layout: sidebar/details-panel sizes, spacing, and information density.
  - [ ] Hierarchy clarity: indentation, connecting lines, task/folder icons,
    and indicators for shared items.
  - [ ] Visual style: colours, fonts, button styles, and light/dark themes.
  - [ ] Interactions: clearer drag-and-drop targets, access to common actions,
    and keyboard navigation.
  - [ ] Settings and filters: make completion inheritance, visibility options,
    and complex filters easier to understand.
  - [ ] Feedback: clearer saving/saved indicators, errors, confirmations,
    and empty views.
  - [ ] Smaller screens: adapt layouts for smaller desktop windows and,
    later, phones.
- [ ] Version/change history (later idea): decide how to inspect and restore
  earlier changes before implementing it.

## Agreed app fixes from physical testing

Recorded on 2026-10-14 on the Pixel 9 Pro running GrapheneOS. These are
approved follow-up tasks; this entry records the reports, not completed fixes.

- [ ] Unify saving/recovery policy, warning UI and diagnostics across platforms.
  Follow the [cross-platform save plan](cross-platform-save-plan.md) and
  [shared-first architecture workflow](shared-app-architecture.md).
  - [x] Document layer ownership and mandatory shared-first guidance in AGENTS.md.
  - [x] Define a typed shared document-adapter contract and one save coordinator.
  - [x] Route desktop external writes through that coordinator, preserving atomic
    publication and private recovery rather than merely wrapping existing saves.
  - [x] Extract Android policy into the coordinator and safely migrate bindings.
  - [x] Connect Windows/Linux filesystem access with conservative identity checks.
  - [x] Share warning dialogs, confirmation actions and private diagnostic export.
  - [x] Verify shared scenarios, migration and native Windows/Linux/Android checks.
  - [ ] Record physical acceptance on Pixel, Windows and Fedora before stable release.
  Shared policy/adapter and migration tests pass locally (45 Dart tests, 56 Rust
  tests); real Linux UI checks include rename → pending edits → explicit
  reconnection without recreating the old path. All native jobs and complete
  package validation passed in run 38534530095 on 2026-10-14, including Windows
  installer upgrade/removal and installed Fedora RPM checks. See
  [all-platform acceptance](shared-saving-acceptance.md).

- [ ] High priority: trustworthy document connection, save status, and recovery.
  Implementation plan: [document saving and recovery](document-save-recovery-plan.md).
  Implemented in the task branch; automated checks cover 53 Rust tests, 23 Dart
  adapter/controller/popup tests, seven Kotlin writer checks, and both host UI
  integration tests. Physical acceptance remains outstanding; follow the
  [Pixel test guide](document-save-phone-test.md) before stable publication.
  - [ ] Reproduce the Pixel/GrapheneOS report: open Tasks_copy.ihtd, background
    IHTD, rename it to Tasks_copy_copy.ihtd in Files, return and edit a task.
    Reported behavior: old filename remains with Saved to file; reopening the
    renamed document shows Pending save, then opening the edited task changes
    it to Saved to file. Establish which bytes actually reached which document.
  - [x] Revalidate document identity, current name, access, and external changes
    when resuming and before publishing. Android providers may retain a valid
    document URI through a rename; distinguish this from lost access rather
    than assuming a filename change necessarily disconnects the document.
  - [x] Compare current provider metadata with remembered metadata and compare
    document contents with the last confirmed content hash. Distinguish a
    rename with unchanged contents from a rename plus external content changes.
    Size, modification time, and capability flags are supporting evidence only:
    providers may omit/stale them, and write capability does not guarantee saves.
  - [x] Explain only confirmed facts. An inaccessible URI may mean deletion,
    movement, revoked permission, or an unavailable provider; do not claim a
    specific cause without evidence. A same-named replacement is not proof of
    document identity and must be explicitly selected/verified before reconnecting.
    Do not promise immediate detection while Android has suspended the app.
  - [x] Agreed behavior: detecting an external rename requires a visible yellow
    warning and pauses automatic publishing pending explicit reconnection,
    even if the provider still permits access through the original URI.
    For a missing/moved/inaccessible document, show a yellow connection warning
    as soon as detected, including on return from the background.
  - [x] Edits while disconnected or awaiting reconnection remain locally
    recoverable; show a persistent yellow Pending changes — not saved to file
    warning. Never describe a private working-copy save as Saved to file.
  - [x] Show red for a confirmed serious save failure, such as a reachable
    destination repeatedly refusing writes or failing read-back verification.
    Include readable text/icons so severity does not rely on colour alone.
  - [x] Provide three levels of issue information: a short clickable yellow
    warning/red error for everyday users; an explanatory popup with safe next
    steps; and an Advanced details section with Export diagnostic log.
  - [x] Keep the short warning/error visible until the underlying issue is
    resolved. Opening the popup or advanced details must not trigger publishing,
    dismiss pending edits, or imply that the problem has been resolved.
  - [x] In the popup, state what changed, what is known versus uncertain, whether
    edits reached the external file or are retained locally, and the applicable
    confirm/reconnect/retry/review/save-copy actions. For a verified rename with
    unchanged contents, use wording such as: Filename changed from
    "Tasks_copy.ihtd" to "Tasks_copy_copy.ihtd". Contents are unchanged.
    Confirm this file to continue saving. For changed contents, require review
    before applying pending edits; never silently overwrite external changes.
  - [x] Export privacy-preserving diagnostic logs by default: omit task titles,
    notes, collection contents, filenames/paths, and full document identifiers.
    Include useful technical context such as app/OS versions, event timestamps,
    operation/error codes, connection/pending/recovery state, and redacted
    provider errors; use anonymous references to correlate document events.
  - [x] Offer explicit opt-in for additional diagnostic information, explaining
    the fields included before export. Keep credentials/secrets out of all logs;
    exporting is user initiated and does not automatically upload diagnostics.
  - [x] Verify redaction of provider exception messages and exported logs, and
    verify popup actions and severity transitions for each file-access scenario.
  - [x] Saved to file requires confirmation that the latest edits reached the
    intended external document; refresh the displayed filename after verified
    reconnection and keep connection status separate from pending-edit status.
  - [x] Explain and verify recovery ownership when reopening/reselecting a
    document: no silent transfer of another document's pending edits and no
    automatic overwrite triggered merely by opening a task/editor. Provide
    explicit reconnect/retry/save-copy choices before applying pending edits.
  - [ ] Preserve working/recovery copies through failed saves, document switches,
    process restart, and APK updates. Verify rename, move, delete, permission
    revocation, external edits, write failure, and successful reconnection on
    the actual Pixel; treat this as a blocker for stable Android publication.

- [ ] Minor layout and clipping fixes (shared UI, Android system bars).
  Implementation sequence: [dialog clipping and system-bar surface plan](layout-polish-plan.md).
  - [x] Unify system-bar backgrounds with adjacent app surfaces so the Pixel
    status/gesture-bar areas do not form differently coloured strips.
    Shared surface painting and Android window flags are implemented; actual
    phone/navigation-mode appearance remains an acceptance item below.
  - [x] Define shared theme surface colours instead of independent literals.
    Paint the complete Drawer, including top/bottom SafeArea inset regions,
    with the sidebar colour; explicitly control its background and surface tint.
    Preserve safe spacing below the status bar and above the gesture area.
  - [x] Make the Android status-bar backdrop match the app header when the
    drawer is closed, and the drawer backdrop match its content when open.
    Paint the appropriate Flutter surface behind transparent edge-to-edge
    system bars rather than relying only on Android bar-colour setters.
  - [x] Configure system-overlay icon brightness for readable clock/status and
    navigation icons; inspect navigation contrast enforcement and drawer scrim
    behavior so opening/closing the drawer does not introduce colour seams.
    Do not force the status and bottom bars to one colour when their adjacent
    surfaces differ; each should visually continue its adjoining surface.
  - [ ] Verify colour continuity on the Pixel/GrapheneOS with drawer open/closed,
    scrolling, dialogs, keyboard transitions, and portrait/landscape. Check
    gesture navigation and three-button navigation if enabled; retain icon
    contrast and validate any future dark theme with the same surface rules.
  - [x] Edit view: fix clipping at the top and bottom of the scrollable rules
    area when scrolling in either direction. Ensure field labels, rule cards,
    and Add condition remain fully readable and reachable at the scroll limits.
  - [x] New task: prevent the floating Title label from being cut off when the
    keyboard opens and the title field receives focus.
  - [ ] Verify both dialogs on the physical Pixel with the keyboard open/closed,
    including scroll limits, large text, and portrait/landscape layouts.
    Use [layout acceptance](layout-polish-acceptance.md). Shared regression tests
    cover constrained phone/desktop layouts, keyboard transitions and 2x text;
    host paint checks are separate from native system-bar acceptance.
    Automated/native verification completed at `e9d1346`:
    [all-platform run 38552777010](https://github.com/Plexyer/ihtd/actions/runs/38552777010)
    passes, with 64 Dart tests and 13 Python checks. Permanent-key candidate
    0.2.2 build 9 also passes ELF/ZIP 16 KB checks. Physical checks stay open.
- [ ] Rework the new/edit view rule editor for clarity and ease of use.
  Implementation handoff: [infix expression-editor plan](view-expression-editor-plan.md).
  Owner approved the infix design and Option-A narrow layout on 2026-10-14;
  shared implementation and automated verification are complete; physical
  acceptance remains pending. See [acceptance guide](view-expression-editor-acceptance.md).
  - [x] Address owner feedback: the current nested cards, repeated Rule labels,
    large dropdown fields, and action layout feel cluttered and unintuitive,
    especially on the Pixel's narrow screen. This is an interaction/layout
    rework, separate from fixing the scroll clipping reported above.
  - [x] Review the design with the owner: conditions joined by infix operators;
    circular plus slots and scoped chain-end addition; AND/OR begins the next
    row on phones (Option A), with inline layout where wider screens allow it.
  - [x] Implement compact editable summaries and parentheses for mixed groups;
    visually combine nested AND/AND and OR/OR, preserving XOR/NOT boundaries.
    Preserve saved matching, creation defaults and deleted-container warnings.
  - [x] Explain ALL/AND and ANY/OR in plain language and make their scope clear;
    keep adding, editing, and removing conditions/groups easy to discover.
  - [x] Give Save/Cancel clear placement and separate secondary/destructive
    actions so they do not dominate the rule editor. Review tag creation's
    placement within the condition workflow.
  - [x] Preserve saved filter structure, creation hints, IDs and preferences;
    verify simple/mixed/deep rules, scoped additions, draft cancellation, stale
    editor guards, duplicate names and deleted-container repair. Automated
    coverage includes 97 Flutter tests, clean analysis, 67 Rust tests and 13
    architecture/release checks; native desktop/phone checks are recorded in
    the implementation plan.
  - [ ] Physically verify the new editor on Pixel/GrapheneOS, Windows and Fedora:
    scoped pluses, every leaf type, mixed/XOR/NOT groups, large text, keyboard,
    rotation/resize, save/cancel, repair and pending external-file publication.
- [ ] Add placement-aware Unlink/Delete actions for both tasks and folders.
  Implementation handoff: [Unlink/Delete plan](unlink-delete-plan.md).
  Owner semantics confirmed 2026-10-14. Shared implementation and automated
  domain/UI checks are complete; physical acceptance remains pending.
  The 2026-10-28 backlog above revises this baseline's menu, global Delete and
  blocked-child Unlink behavior. Checked entries below record the earlier
  implementation; they are not evidence that the new behavior is implemented.
  - [x] When an item has two or more actual placements, label the action
    Unlink and remove only the selected placement. Preserve the shared item,
    its data, and its remaining placements.
  - [x] When an item has exactly one placement, label the action Delete and
    delete the item when that last placement is removed.
  - [x] Count actual hierarchy/root placements, not appearances in filtered
    views; update the label as links are added or removed.
  - [x] Agree child handling and action protection: confirm Delete; Unlink
    immediately. Recursively delete children without surviving placements;
    preserve shared branches linked elsewhere. Linked folders share children
    across all appearances. Undo/trash are outside this task.
  - [x] Verify task/folder actions with one and multiple placements, including
    nested and top-level placements, saved views, and persistence after reopen.

  - [x] Keep views referring to deleted containers, with unchanged Boolean scope.
    Give affected views a yellow shade and a minor hierarchy warning identifying
    the rule to review; the editor shows Deleted container. Repair clears warnings.
  - [x] Reject stale approval and switches to another working copy, including
    copies with the same document ID. Flush drafts; invalid drafts block removal.
  - [x] Automated verification: 67 Rust tests, 75 Flutter tests, clean analysis
    and real Linux UI/reopen/disconnected-file integration passed. Development
    check run `38568092620` passed for runtime commit `6e06079`. Native phone-layout
    integration and signed ARM64 build 10 passed; permanent certificate and
    ZIP/ELF 16 KB alignment verified.
  - [ ] Follow [physical removal acceptance](unlink-delete-acceptance.md) on Pixel,
    Windows and Fedora, including disconnected-file retention and reconnect.

## Agreed release and update work

Work through this section in dependency order. Do not offer automatic updates
until the corresponding packages have stable identities, signing, versioning,
and verification.

- [ ] Establish the shared development and release foundation.
  - [ ] Use `master` only for reviewed, releasable code and protect it from
    direct everyday changes.
  - [x] Create `development` for integration of the next version; merge
    short-lived `feature/*` and `fix/*` branches into it through pull requests.
  - [x] Document when to use temporary `release/x.y.z` stabilization branches
    and require their fixes to be merged back into `development`.
  - [x] Document `hotfix/*`: branch from `master`, merge into `master`, then
    merge the same fix back into `development`.
  - [x] Define one authoritative application version shared by Android,
    Windows, Fedora, package metadata, filenames, and release notes.
  - [x] Build every platform for an official release from the same immutable
    `vX.Y.Z` Git tag; do not maintain permanent platform source branches.
- [ ] Rework GitHub Actions around pull requests, `master`, and version tags.
  Implementation is in the coordinated `release.yml` workflow. Full native CI
  validation and a real tagged-release exercise must pass before checking off
  the operational release tasks below. Administrator branch protection remains
  pending because the integration credential cannot access that API.
  - [x] On development PRs, run Rust tests, Flutter analysis and Dart adapter
    tests; on master PRs, build/verify all platforms and retain testing artifacts
    for 14 days. Neither PR workflow publishes a release.
  - [x] Avoid duplicate builds on ordinary pushes/merges into development and
    master. Full builds run for master PRs, version tags, or manual requests.
  - [x] Update development's required check to `Development checks`; master
    continues requiring `All platforms validated`. Requires an administrator.
  - [x] On a `vX.Y.Z` tag, test and build Android, Windows, and Fedora from the
    tagged commit, then attach all verified outputs to one GitHub Release.
    v0.2.1 completed all jobs and draft uploads; downloaded checksums verified.
  - [ ] Publish a stable release only after every required platform succeeds;
    include generated release notes, installation instructions, package sizes,
    and SHA-256 checksums.
  - [ ] Keep downloadable application files in GitHub Releases. Use GitHub
    Packages only if a future registry/container use case requires it.
- [ ] Finish production-ready packages and signing.
  - [ ] Android: establish one backed-up permanent release-signing key, store
    it and its password as protected GitHub Actions secrets, document recovery
    ownership, and verify that a newly built APK updates an earlier public APK
    without losing app data.
    - [x] Generate an encrypted release keystore and pin its public SHA-256
      certificate in source; keep the password separate and private.
    - [x] Implement separate protected tag signing, certificate verification,
      fail-closed release assembly, and secure local generation/upload tools.
    - [ ] Owner downloads the keystore/password at home, keeps independent
      backups, and verifies recovery before activating public releases.
    - [x] Administrator configures tag-only android-release environment and
      its three signing secrets. Tag policy verified; owner reconfirmed all
      three secret names on 2026-10-15. Integration secret API returns HTTP 403.
    - [x] Forward the three named signing secrets through the reusable-workflow
      caller, with optional declarations for unsigned PR/branch builds.
    - [ ] Complete a production tag run with the corrected secret handoff and
      verify every draft asset. v0.2.3 native jobs passed but signing received
      empty secrets; preserve its tag and use [0.2.4](release-0.2.4.md) next.
    - [ ] Verify two permanent-key APKs on the actual Pixel as an in-place
      update, preserving working/recovery copies and document grants.
  - [ ] Android: publish a clearly named ARM64 APK compatible with the Pixel 9
    Pro/GrapheneOS target and verify its signature and 16 KB alignment.
  - [x] Windows: add an Inno Setup `.exe` installer while retaining the complete
    portable `.zip` bundle.
    - [x] Implement per-user setup, shared-version packaging and EXE/ZIP release
      assembly with checksums; include app-local redistributable runtime DLLs.
    - [x] Pass the native Windows installer verification workflow (2026-10-13,
      run 38405384372); both downloadable packages and checksums were uploaded.
    - [ ] Verify the interactive wizard and Explorer/default-app behavior on
      an actual Windows 11 PC before stable publication.
  - [x] Windows: make the installer support upgrades, clean uninstall, Start
    Menu integration, optional desktop shortcut, preserved user data, and
    `.ihtd` file association.
    - [x] Implement stable upgrade identity, recorded-file uninstall, shortcuts,
      optional Open-with registration and startup document loading.
    - [x] Verify upgrade/removal and real collection/recovery preservation on
      the native Windows runner. Physical Windows 11 validation remains above.
  - [ ] Windows: add trusted code signing before automatically executing a
    downloaded installer; consider MSIX later only for Store/enterprise needs.
  - [ ] Fedora: retain the installable `.rpm` and optional portable `.tar.gz`,
    with desktop/icon integration, clean upgrade/removal, and `.ihtd`
    association.
  - [ ] Fedora: sign the RPM and document verification; later decide whether
    public usage justifies hosting a signed DNF repository.
- [x] Define the open-source license with the owner: elicit their desired terms,
  compare suitable licenses, and add the chosen license/notices before public
  announcement. Owner confirmed AGPLv3 including network copyleft on 2026-10-15;
  AGPL-3.0-only files/metadata/notices are added. See [licensing](licensing.md).
  - [ ] Complete native dependency notice/compatibility inventory before stable
    binary distribution; preserve separate third-party runtime/library licenses.
- [x] Prepare safe public distribution of the source and release assets.
  Follow [public repository guide](public-repository-guide.md): audit full Git
  history/all refs and public-facing assets/metadata for confidential material,
  remediate/rotate any exposed secrets, choose a license, and obtain owner action
  before changing visibility. GitHub Secrets remain private; Git history does not.
  - [x] Record automated audit scope/results in [publication audit](publication-audit.md):
    no detected credential matches in history/available scanned surfaces.
  - [x] Correct literal quotes in GitHub master/development/version-tag rulesets
    and android-release tag policy; verified corrected patterns match actual refs.
    Follow [exact correction steps](public-repository-guide.md#required-correction-found-during-the-audit).
  - [x] Owner reviews privacy/license/protection settings, then changes visibility;
    signed-out public pages/downloads and effective protections verified. Stable
    updater release/signing and actual phone tests remain open below.
- [ ] Add a shared, privacy-conscious update experience.
  Implementation handoff: [update workflow plan](update-workflow-plan.md).
  Owner approved 2026-10-15: move drawer menu beside current view name; header
  blue arrow opens release-information/Download popup; confirmation closes popup,
  animated circle/downward arrow shows download; verified package becomes green
  tick. Downloads continue while minimized/locked using Android background
  facilities and its normal notification. Tap tick invokes Android's native
  permission/installer UI without an
  extra IHTD installation confirmation. Reconcile actual version on next launch;
  Android automatic reopening is not guaranteed. Public stable Releases, not
  master merges/drafts/test branches, advertise updates. Shared implementation
  is complete; physical acceptance/public distribution
  and desktop signing remain pending. Follow [update acceptance](update-acceptance.md).
  - [x] Check the latest compatible GitHub release infrequently, compare its
    semantic version with the installed version, and show a small update icon
    only when a newer release is available.
  - [x] Add an update screen with version, release notes, download size, and a
    user-confirmed action; also provide **Check for updates** and an option to
    disable automatic checks.
  - [x] Keep stable releases as the default channel; expose development builds
    only through an explicit opt-in if that channel is added.
  - [ ] Verify downloaded metadata/package authenticity before offering an
    install action, and show useful offline, download, and verification errors.
    - [x] Android cryptographic APK verification against installed/pinned signer,
      package/build/API/ABI and hash/size; shared errors, no unverified green tick.
    - [ ] Windows/Fedora trusted package signing and automatic handoff; current
      shared UI uses an explicit manual release-page fallback.
  - [ ] Physically validate the update flow on Pixel/GrapheneOS, Samsung, Windows
    and Fedora. Public feed and first updater-enabled manual installation required.
- [ ] Implement the platform-specific update handoff.
  - [x] Android/GrapheneOS: download the signed ARM64 APK and hand it to the
    system package installer; explain the one-time "install unknown apps"
    permission and require Android's normal user confirmation.
  - [ ] Android: confirm an update preserves app data, retained document grants,
    working copies, and recovery data on the physical Pixel.
  - [ ] Windows: first provide a guided download/open of the signed setup EXE;
    later add verified download, graceful app shutdown, installer launch, and
    restart if that flow proves reliable.
  - [ ] Fedora: initially open/download the signed RPM and hand installation to
    Fedora's graphical package tooling rather than overwriting package-owned
    files from inside IHTD.
  - [ ] Fedora: if a signed DNF repository is introduced, let DNF/GNOME Software
    provide normal system updates; keep portable `.tar.gz` updates manual.

## Optional features to discuss

- [ ] Undo/redo for edits, moves, and completion changes.
- [ ] Quick search without creating a saved filter view.
- [ ] Import exported JSON, with rules for restoring versus merging collections.
- [ ] Tag management: rename, delete, and optionally merge tags in the interface.
- [ ] A recovery screen for finding and restoring the local recovery snapshots.
- [ ] Convenience controls: keyboard shortcuts, multi-selection, and bulk actions.

Already implemented: shared IDs and arbitrary-depth hierarchy, task/folder
conversion, completion inheritance, per-view visibility, saved filters,
notes/dates/priorities/tags, portable .ihtd files, autosave/external reload,
JSON/Markdown/CSV exports, and drag-and-drop moves/reordering.

Built-in cloud integration and concurrent editing remain outside the agreed
prototype scope. Normal filesystem mounts/sync clients provide file access.
