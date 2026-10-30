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
Enabled counters display zero. None-priority tasks still count toward Total.

Each indicator independently resolves collection defaults, optional shared
parent overrides, then parent/view overrides. Total and High default on; ratio,
Medium, Low and next date default off. Resetting one override resumes live
inheritance; changing one view does not freeze other settings or views.

Owner-confirmed presentation (2026-10-30):

- With next date enabled and no eligible date, show nothing for that indicator;
  do not reserve space for an empty summary panel.
- Show summaries only on items currently having children, equally for tasks
  and folders. Empty folders and leaf tasks have no summary. Parents whose
  children are all excluded by the view/tab still show enabled zero counters.

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

Shared Flutter `SummaryIndicators` renders the Rust response without recalculating
defaults, filtering or counts. Reuse `PriorityIcon` at 14 pixels. Normal layouts
stack priority icon/count pairs within the existing row control height, keeping
card height unchanged. Counters precede the date so a long date cannot hide
their numbers; date/total labels can ellipsize with the full tooltip available.
Very narrow/deep cards use a horizontally scrollable summary region. Enlarged
text uses a horizontal run instead of shrinking text or adding a tall counter
stack. The full summary has one accessible description, independent of scrolling,
color or ellipsis. Existing row actions and the parent's own priority remain.

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

Host verification passed: 104 Rust tests, 190 Flutter unit/widget tests,
17 Python checks, Flutter analysis and native Linux summary/desktop/phone-layout
integration. A rendered preview was reviewed at normal and enlarged text sizes.
The ARM64 release APK built and passed native ELF LOAD and APK ZIP 16 KB
alignment checks. The final display choices were verified with targeted widget
and core checks. These checks do not establish physical acceptance.
