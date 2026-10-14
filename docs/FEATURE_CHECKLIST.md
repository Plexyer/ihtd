# Feature checklist

Updated 2026-10-14 for physical Android feedback and agreed release/update
workflow. Unchecked suggestions are not approved requirements unless they are
listed under "Agreed release and update work"; clarify their behavior before
implementing them.

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
  - [ ] Define a typed shared document-adapter contract and one save coordinator.
  - [ ] Route desktop external writes through that coordinator, preserving atomic
    publication and private recovery rather than merely wrapping existing saves.
  - [ ] Extract Android policy into the coordinator and safely migrate bindings.
  - [ ] Connect Windows/Linux filesystem access with conservative identity checks.
  - [ ] Share warning dialogs, confirmation actions and private diagnostic export.
  - [ ] Verify shared scenarios, migration and native Windows/Linux/Android checks.
  - [ ] Record physical acceptance on Pixel, Windows and Fedora before stable release.

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

- [ ] Minor Android layout and clipping fixes.
  - [ ] Unify system-bar backgrounds with adjacent app surfaces so the Pixel
    status/gesture-bar areas do not form differently coloured strips.
    Current sources: main.dart sets scaffold/surface to #f5f7fa; app_shell.dart
    paints _FileBar white and _Sidebar #eef2f7, while Drawer uses its Material 3
    default and wraps only its child in SafeArea. The uncovered drawer inset
    areas therefore do not explicitly share the sidebar's background.
  - [ ] Define shared theme surface colours instead of independent literals.
    Paint the complete Drawer, including top/bottom SafeArea inset regions,
    with the sidebar colour; explicitly control its background and surface tint.
    Preserve safe spacing below the status bar and above the gesture area.
  - [ ] Make the Android status-bar backdrop match the app header when the
    drawer is closed, and the drawer backdrop match its content when open.
    Paint the appropriate Flutter surface behind transparent edge-to-edge
    system bars rather than relying only on Android bar-colour setters.
  - [ ] Configure system-overlay icon brightness for readable clock/status and
    navigation icons; inspect navigation contrast enforcement and drawer scrim
    behavior so opening/closing the drawer does not introduce colour seams.
    Do not force the status and bottom bars to one colour when their adjacent
    surfaces differ; each should visually continue its adjoining surface.
  - [ ] Verify colour continuity on the Pixel/GrapheneOS with drawer open/closed,
    scrolling, dialogs, keyboard transitions, and portrait/landscape. Check
    gesture navigation and three-button navigation if enabled; retain icon
    contrast and validate any future dark theme with the same surface rules.
  - [ ] Edit view: fix clipping at the top and bottom of the scrollable rules
    area when scrolling in either direction. Ensure field labels, rule cards,
    and Add condition remain fully readable and reachable at the scroll limits.
  - [ ] New task: prevent the floating Title label from being cut off when the
    keyboard opens and the title field receives focus.
  - [ ] Verify both dialogs on the physical Pixel with the keyboard open/closed,
    including scroll limits, large text, and portrait/landscape layouts.
- [ ] Rework the new/edit view rule editor for clarity and ease of use.
  - [ ] Address owner feedback: the current nested cards, repeated Rule labels,
    large dropdown fields, and action layout feel cluttered and unintuitive,
    especially on the Pixel's narrow screen. This is an interaction/layout
    rework, separate from fixing the scroll clipping reported above.
  - [ ] Propose and review a simpler layout with the owner before implementing;
    make individual conditions, their values/comparisons, and group boundaries
    easy to scan without excessive nesting or wasted vertical space.
  - [ ] Explain ALL/AND and ANY/OR in plain language and make their scope clear;
    keep adding, editing, and removing conditions/groups easy to discover.
  - [ ] Give Save/Cancel clear placement and separate secondary/destructive
    actions so they do not dominate the rule editor. Review tag creation's
    placement within the condition workflow.
  - [ ] Preserve existing filter semantics and saved-view compatibility; verify
    simple and nested rules, long labels, large text, keyboard use, and touch
    scrolling on the physical Pixel, plus usability on desktop.
- [ ] Add placement-aware Unlink/Delete actions for both tasks and folders.
  - [ ] When an item has two or more actual placements, label the action
    Unlink and remove only the selected placement. Preserve the shared item,
    its data, and its remaining placements.
  - [ ] When an item has exactly one placement, label the action Delete and
    delete the item when that last placement is removed.
  - [ ] Count actual hierarchy/root placements, not appearances in filtered
    views; update the label as links are added or removed.
  - [ ] Before implementation, agree how deleting the last placement handles
    children, including shared descendants, and whether confirmation or undo
    is needed. Never silently delete descendants still linked elsewhere.
  - [ ] Verify task/folder actions with one and multiple placements, including
    nested and top-level placements, saved views, and persistence after reopen.

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
    - [ ] Administrator configures tag-only android-release environment and
      its three signing secrets; integration secret API returns HTTP 403.
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
- [ ] Add a shared, privacy-conscious update experience.
  - [ ] Check the latest compatible GitHub release infrequently, compare its
    semantic version with the installed version, and show a small update icon
    only when a newer release is available.
  - [ ] Add an update screen with version, release notes, download size, and a
    user-confirmed action; also provide **Check for updates** and an option to
    disable automatic checks.
  - [ ] Keep stable releases as the default channel; expose development builds
    only through an explicit opt-in if that channel is added.
  - [ ] Verify downloaded metadata/package authenticity before offering an
    install action, and show useful offline, download, and verification errors.
- [ ] Implement the platform-specific update handoff.
  - [ ] Android/GrapheneOS: download the signed ARM64 APK and hand it to the
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

- [ ] Delete items everywhere, clearly distinguished from removing one placement;
  decide how shared subitems and recovery/trash should behave.
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
