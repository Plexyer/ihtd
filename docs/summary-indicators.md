# Direct-child summary indicators

Implementation candidate for step 7 / specification item 5, 2026-10-30.
Physical acceptance remains open. Settings were established in
[collection settings](collection-settings.md); this step consumes them.

## Metric contract

Summaries belong to the parent item, not its placement path. Count its direct
child tasks only, once per direct link. Exclude child folders, deeper descendants
and ancestors retained only for context. The child itself must match the view's
filter. Linked appearances of a parent show the same summary; a shared task may
contribute to each different parent directly containing it.

| Enabled indicator | Value |
| --- | --- |
| Total | Matching direct child tasks in the current completion tab |
| Completed / total (with Total enabled) | `Total: completed / total` across both tabs, still matching the view's filter |
| High/Medium/Low priority | Matching direct child tasks of that priority in the current tab |
| Next due date | Earliest matching direct child's date today or later, in the current tab |

The ratio replaces the ordinary Total; it never enables Total implicitly.
Completion filtering is strict even if visibility preferences retain completed
children in the Unfinished outline. Context-only children do not contribute
just because a matching descendant makes them visible. Collapsing a parent
does not change its summary. Overdue dates are ignored; today's date qualifies.
Enabled Total can display zero. Priority pairs are shown only for enabled,
nonzero counts. None-priority tasks still count toward Total. The later owner
layout revision below supersedes the initial request to show zero priority pairs.

Each indicator independently resolves collection defaults, optional shared
parent overrides, then parent/view overrides. Total and High default on; ratio,
Medium, Low and next date default off. Resetting one override resumes live
inheritance; changing one view does not freeze other settings or views.

Owner-confirmed presentation (2026-10-30):

- With next date enabled and no eligible date, show nothing for that indicator;
  do not reserve space for an empty summary panel.
- Show summaries only on items currently having children, equally for tasks
  and folders. Empty folders and leaf tasks have no summary. Parents whose
  children are all excluded by the view/tab can still show an enabled Total of
  zero; zero priority counts are hidden.
- Total and Next date occupy the bottom of the card on the same line, with
  Total first and Next date to its right.
- Show only enabled nonzero priority pairs, in High/Medium/Low order. Center
  that vertical stack in the card, including when only one or two pairs remain.
- Approved mockup refinement: keep the title/metadata, folder/checkbox, expand
  control and menu centered in the main body above the footer. The priority
  stack uses the full card height including the footer, so its centerline sits
  slightly below the main body's. Do not pin the title to the top of the card.

## Shared calculation and rendering

`crates/ihtd_core/src/indicators.rs` owns direct-child calculation. A read-only
`IndicatorQuery` indexes direct links once and caches each parent's summary for
the query. Resolve settings before filtering children. Rule-hidden direct child tasks are
counted even when every configurable metric is disabled. Disabled fields are omitted;
enabled counters serialize zero, and an enabled missing date serializes null.
Ratio work runs only when both Total and Completed / total are enabled.

`presentation::outline_with_summaries` decorates only projected rows, reusing
cached results for shared appearances. Ordinary `outline` remains undecorated
for structural move planning. Product `query` supplies the local `today` date;
legacy/internal queries omitting it retain their old lightweight response.
Invalid dates fail without mutation. No host adapter defines metric policy.

Shared Flutter `SummaryIndicators` renders only the Total/date footer, without
recalculating defaults, filtering or counts. `SummaryItemContent` centers the
title/metadata in the main body and places the footer at the bottom of the card.
`SummaryBodyControls` reserves the same measured footer extent beneath leading
controls and the menu, preserving their alignment with the title. Footer metrics
follow the actual font and text scale, rather than a guessed fixed offset.
The footer keeps Total and Next date on one line and scrolls horizontally when a narrow card or enlarged text
needs more room. Each full value remains available in a tooltip/accessible label.

`SummaryPriorityCounts` hides zeroes from the derived response and reuses
`PriorityIcon` at 14 pixels. The card stretches its content to one common height
and centers the nonzero priority stack vertically. At ordinary text size three
pairs fit within the existing 48-pixel main body; the footer has its own space
below it. Large text or more title/metadata content can grow the card to keep
everything readable; no text is
shrunk or vertically clipped. Footer and priority stack have separate accessible
descriptions. Existing row actions and the parent's own priority remain.

`AppController` supplies the device's local calendar date and refreshes read-only
summaries when polling/resuming observes a new date or timezone day. Queries do
not commit item drafts, increment the model revision or publish the external
file. Accepted field/completion/link/settings/view changes already refresh rows.
Private drafts, external-save barriers and recovery behavior remain unchanged.

## Compatibility and acceptance

These are derived query fields, not new stored collection data. No file-format
or semantic conversion, migration, version bump or signing change is needed.
The native test opens a frozen distributed schema-2 fixture, verifies query-only
byte/revision preservation, checks actual metrics/settings and local day rollover,
then verifies private draft and disconnected-file recovery across restart.
Windows and Fedora native pipelines include that scenario.

- [ ] Pixel/GrapheneOS and Samsung: verify counters, zeroes, ratio on both tabs,
  filtering, next dates, settings inheritance, collapsed/shared parents and
  midnight/resume behavior with real document providers.
- [ ] Native Windows/Fedora: verify mouse/tooltip/scrolling, scaling and keyboard
  behavior, plus cross-platform collection transfer and upgrades.
- [ ] Verify full accessibility descriptions and large-text/deep-hierarchy
  layouts, retaining usable titles, own priority and action menus.

Initial implementation verification passed: 104 Rust tests, 190 Flutter unit/widget tests,
17 Python checks, Flutter analysis and native Linux summary/desktop/phone-layout
integration. A rendered preview was reviewed at normal and enlarged text sizes.
The ARM64 release APK built and passed native ELF LOAD and APK ZIP 16 KB
alignment checks. The final display choices were verified with targeted widget
and core checks. The later footer/priority layout was verified with the 190-test
Flutter suite, analysis, 17 Python checks, native Linux integrations and rendered
previews of one/two/three priorities and enlarged text. These checks do not
establish physical acceptance.

## Rule-hidden children (2026-10-31)

The derived `hidden_by_rules` field is present only for a positive count of
**direct child tasks** failing the current view filter. It ignores completion-tab
selection, collapse and visibility preferences; folders and deeper descendants
are excluded. Nonmatching tasks still visible as ancestor context for a rule-matching
descendant are not labeled hidden. It does not change existing Total/ratio/priority/date calculations.
It remains available with Total/all configurable metrics off; no settings or
collection migration is introduced.

The footer appends a compact hidden-items icon/count after Total and Next date.
It has a tooltip/accessibility label, scrolls with the existing footer at narrow
widths, and reserves only a 24px line minimum when present. The title/main controls
stay centered above the measured footer; priorities stay centered against the
whole card. No zero-count icon appears.

Tapping explains rule filtering and offers Open in All tasks. The controller
checks file/view ownership and item existence before/after resolving drafts,
uses the protected view ID, selects the parent’s completion tab, expands the
selected path and opens that parent. Existing completion/visibility preferences
still apply. Keep editing cancels navigation; stale file/view dialogs cannot
navigate another collection. This is read-only navigation, never a rule rewrite.

Physical phone/desktop acceptance: check hidden-only footers, long values, large
text/deep indentation, icon touch/tooltip access and Save/Discard/Keep editing on
navigation. Shared unit/native verification is recorded in the task PR.
