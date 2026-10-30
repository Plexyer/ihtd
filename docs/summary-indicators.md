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

## Shared calculation and rendering

`crates/ihtd_core/src/indicators.rs` owns direct-child calculation. A read-only
`IndicatorQuery` indexes direct links once and caches each parent's summary for
the query. Resolve settings before filtering children; if all effective metrics
are disabled, skip filtering/count/date work. Disabled fields are omitted;
enabled counters serialize zero, and an enabled missing date serializes null.
Ratio work runs only when both Total and Completed / total are enabled.

`presentation::outline_with_summaries` decorates only projected rows, reusing
cached results for shared appearances. Ordinary `outline` remains undecorated
for structural move planning. Product `query` supplies the local `today` date;
legacy/internal queries omitting it retain their old lightweight response.
Invalid dates fail without mutation. No host adapter defines metric policy.

Shared Flutter `SummaryIndicators` renders only the Total/date footer, without
recalculating defaults, filtering or counts. `SummaryItemContent` places it below
the title/metadata at the bottom of the card. The footer keeps Total and Next
date on one line and scrolls horizontally when a narrow card or enlarged text
needs more room. Each full value remains available in a tooltip/accessible label.

`SummaryPriorityCounts` hides zeroes from the derived response and reuses
`PriorityIcon` at 14 pixels. The card stretches its content to one common height
and centers the nonzero priority stack vertically. At ordinary text size three
pairs fit within the existing 48-pixel control height. Large text or more title/
metadata content can grow the card to keep everything readable; no text is
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
