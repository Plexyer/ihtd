# Dialog clipping and system-bar surface plan

Created 2026-10-14 for the next implementation session. Planning only: no UI
changes have been made. Start from the latest `development`, read `AGENTS.md`,
requirements and shared architecture, then work through these steps in order.
Record evidence and remaining physical checks here and in `FEATURE_CHECKLIST.md`.

## Scope and completion criteria

Fix the reported edit-view scroll clipping, new-task floating Title label
clipping when the keyboard appears, and mismatched status/navigation-bar
backdrops. Implement responsive dialog and surface behavior once in shared
Flutter UI for Android, Windows and Linux. Android window integration belongs
in its platform layer when necessary.

Keep the current rule structure and filter semantics. The rule-editor redesign,
Unlink/Delete, save policy, package signing and a new dark theme are separate
tasks. Do not mark physical Pixel/GrapheneOS acceptance complete from host tests.

Acceptance:

- Labels, outlines, first/last rules and Add condition are fully readable at
  scroll limits. Partial rows during ordinary scrolling are expected, but
  controls must become completely visible when scrolled into view.
- Keyboard opening, closing and focus changes leave fields and dialog actions
  reachable without overflow, hidden floating labels or overlapping system bars.
- Status and navigation areas continue their respective adjacent app surfaces;
  the two bars need not share one color. Drawer inset regions match its content.
- System icons remain readable and existing safe spacing, scrolling, edits and
  Save/Cancel behavior work on phone and desktop.

## 1. Establish reproductions and inspect constraints

- [ ] Confirm the branch is based on merged development, with a clean checkout.
- [ ] Reproduce with a disposable collection and nested view conditions in
  `app/lib/ui/view_editor.dart`, then new-task autofocus in
  `app/lib/ui/item_editor.dart`. Record screenshots and actual layout bounds at
  both scroll limits, with and without keyboard insets.
- [ ] Inspect AlertDialog content padding, viewport clipping, outline/floating
  label paint bounds, fixed heights, action wrapping and focus auto-scrolling.
  The view currently requests 680 x 560 content; constraints may reduce it.
  Treat these as suspects, not confirmed root causes.
- [ ] Inspect `main.dart`, `_FileBar`, `_Sidebar` and Drawer in `app_shell.dart`.
  Current surfaces include scaffold #f5f7fa, white header, sidebar #eef2f7 and
  default Material 3 Drawer background/tint outside the child SafeArea.
- [ ] Inspect Android MainActivity, manifest and values/values-night styles,
  actual edge-to-edge settings and Flutter overlay behavior with dialogs/drawer.
  Distinguish Flutter paint/tint from native contrast scrims before changing it.

## 2. Fix shared dialog bounds and scrolling

- [ ] Use available constraints, safe insets and keyboard viewInsets to bound
  the dialogs; retain comfortable desktop width without imposing a phone height.
  Account for insets once: do not double-subtract AlertDialog's keyboard padding.
- [ ] Give scroll content enough inner top/bottom padding for floating labels,
  outlines and card paint. Keep normal viewport clipping rather than disabling
  it globally, hiding labels or shrinking fonts to conceal the problem.
- [ ] Ensure the view name/help section cannot consume all remaining height
  with large text or a landscape keyboard. Choose a unified scroll region or
  bounded sections from the measured constraints, keeping actions reachable.
- [ ] Fix the create-task Title field at autofocus and during typing, errors and
  keyboard transitions. Audit the same issue in folder creation and other fields
  that reuse this dialog; avoid copying a second implementation.
- [ ] Keep Save/Create/Cancel and secondary actions usable when they wrap. Verify
  focus traversal, scrolling to focused fields and preservation of unsaved input.
- [ ] Extract a small shared helper only if both dialogs need the same behavior;
  preserve existing rule editing and creation semantics.

## 3. Centralize shared surface colors

- [ ] Define explicit canvas, header and sidebar theme roles in a shared theme
  location (ThemeExtension or existing theme configuration as appropriate).
  Replace relevant independent shell literals without changing task-card accents.
- [ ] Paint the entire Drawer, including SafeArea margins, with the sidebar
  surface. Set its background and surface tint explicitly where defaults alter
  the intended color. Keep sidebar content clear of status/gesture areas.
- [ ] Paint the closed-shell top inset as the header surface and the bottom
  inset as its adjacent content surface. Preserve responsive permanent-sidebar
  layout on desktop and narrow-window drawer layout.
- [ ] Verify top/bottom paint during drawer open/close and its scrim animation:
  the uncovered main area should dim consistently, with no extra inset strips.
  Do not remove the intended modal scrim just to match screenshots.

## 4. Integrate Android system overlays

- [ ] Prefer painting Flutter surfaces behind transparent edge-to-edge system
  bars; modern target SDKs may ignore legacy bar-color setters.
- [ ] Set consistent system icon brightness through shared overlay annotations
  where supported. Keep OS selection out of shared widgets; native Android
  window flags, if required, stay in Android code/bootstrap integration.
- [ ] Check gesture and three-button navigation contrast enforcement before
  changing native flags. Retain readable system controls in every modal state.
- [ ] Verify startup/first frame and OS dark-mode settings do not introduce a
  flash or switch bar icon contrast against the app's current light theme.
  Keep values and values-night native settings consistent with that behavior.
- [ ] Preserve dialog/keyboard overlay restoration when closing routes; avoid
  competing global overlay setters. Explain any necessary platform exception.

## 5. Add focused regression coverage

- [ ] Add meaningful widget/layout tests for first/last rule visibility and
  reachable Add condition, Title autofocus/floating-label paint clearance and
  keyboard appearance/dismissal. Check bounds as well as Flutter exceptions;
  absence of overflow alone does not prove that a label is not clipped.
- [ ] Cover representative 390 x 844 logical phone size, a smaller phone,
  short landscape viewport, large text (including 2x), and narrow/wide desktop.
  Simulate safe padding and keyboard viewInsets independently, with teardown.
- [ ] Check surface values and full inset coverage with drawer closed/open.
  Use focused screenshot/golden evidence if needed for actual paint clipping;
  widget properties alone cannot prove Android system-bar appearance.
- [ ] Extend `integration_test/phone_layout_test.dart` for affected flows while
  retaining existing touch scrolling, drag/drop and editor-flush checks. Keep
  integration data isolated in temporary directories.
- [ ] Run Flutter analysis, relevant widget tests and existing desktop/narrow
  integration tests. Run the architecture checker to keep the shared boundary.
  Run broader domain/storage tests only if those layers change.

## 6. Build candidates and perform platform acceptance

- [ ] Build Android with existing permanent signing identity and an appropriate
  new versionCode. Follow signing/build guides; preserve app data and document
  grants on upgrade. Do not replace keys or commit build outputs.
- [ ] Test on the physical Pixel 9 Pro / GrapheneOS: drawer closed/open,
  scroll extremes, view/task/folder dialogs, title focus, keyboard transitions,
  portrait/landscape, large text, light/dark OS settings and available navigation
  modes. Record build, OS/navigation settings and before/after screenshots.
- [ ] Verify Windows and Fedora responsive dialogs at narrow/wide window sizes
  and scaling; use existing native CI when needed. Keep untested native/physical
  results explicitly pending. Shared UI changes must not break desktop layouts.
- [ ] Recheck that creating/editing/saving views and tasks still works and that
  warning popups, file saving and document recovery behavior remain intact.

## 7. Document and hand off

- [ ] Update requirements with the implemented surface/inset rules, shared
  architecture if helpers or platform hooks were added, and build/test guidance
  for new checks. Link a concise physical acceptance sequence if necessary.
- [ ] Check off only verified clipping/color checklist items. Keep the separate
  view-rule redesign unchecked and explain any remaining acceptance gaps.
- [ ] Commit and push a task branch; open a PR into `development` with root
  causes, final changes, platform exceptions, verification and visual evidence.
  Let the owner merge. Do not publish a stable release as part of this task.

## Suggested implementation checkpoints

1. Reproduction and shared dialog clipping fixes with focused tests.
2. Shared surface ownership and Android overlay integration with visual checks.
3. Candidate verification, checklist/documentation and PR handoff.

Complete and verify each checkpoint before moving on; update this plan when
observed behavior warrants a different implementation.
