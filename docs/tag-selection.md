# Tag selection and recent popularity

Implementation candidate for step 8 / specification item 6, 2026-10-31.
Shared across Android, Windows and Linux; physical acceptance remains open.

## Editing behavior

Task and folder editors show every selected tag above a light divider. Beneath
it are up to the collection's configured number of popular **unselected** tags
and Select other…. The default count is 5; selected tags consume no suggestion
slots. A count of zero hides suggestions while keeping selected tags and the
full picker available. The existing Create tag action stays in the section
header: creation is an immediate separate collection action, while assigning
that tag remains part of the cancellable item draft.

Select other… opens a case-insensitive substring search and multi-select list.
Selections persist across searches. Done applies the entire picker selection
to the current item draft; Cancel, Back/Escape or outside dismissal discards
only the picker changes. Nothing commits to the item until the editor's Save
or its existing valid outside-save behavior. The picker shows duplicate names
with IDs for disambiguation. Its shared responsive form keeps actions reachable
on short/keyboard-constrained/large-text layouts.

Opening the picker captures working path, document UUID, draft session, selected
IDs and tag metadata. A different collection/session cannot receive its result.
If tags or draft selections changed while it was open, reject Done with a
review/reopen message rather than overwriting the newer state. Background ranking
requests are read-only and do not disable the editor, replace snapshots, move
the cursor or commit drafts. Failed ranking offers Retry; selected tags and
Select other remain usable.

## Popularity contract

Only newly assigned tags in an accepted manual item-draft Save count. Existing
items compare final tag IDs against the saved baseline. New items compare them
against the creation view's automatic tag defaults. Unchanged assignments,
removed tags, filter defaults, copied assignments, cancelled/unfinished drafts
and failed saves do not create events. Removing then re-adding a baseline tag
before a single Save has no net new assignment. An accepted private Save counts
even while external publication is pending; retrying publication does not count
it again. Past committed usage remains if an item is later removed; deleting the
tag itself removes its history.

For each tag, sum `count × 2^(-age / halfLife)` across committed assignments.
Use UTC seconds and the current collection half-life, defaulting to three days.
Keeping history means a changed half-life applies to earlier events consistently.
New assignments to other tags can overtake older ones as influence fades. Equal
scores use case-insensitive alphabetical names, then tag ID; collections without
usage history start alphabetically, never seeded from current assignments.
Clock rollback caps negative age at zero instead of amplifying future events.

## Ownership and data safety

`crates/ihtd_core/src/tag_usage.rs` owns ranking, time/history validation and
atomic event recording. Optional `Document.tag_usage` maps each tag ID to UTC
second/count buckets; assignments in the same second aggregate, without storing
item IDs or contents. Scores are computed, never stored. History grows with
committed assignment buckets, not queries, and is retained so changing the
half-life does not lose older information.

`crates/ihtd_app/src/item_drafts.rs` derives manual additions from authoritative
item/view baselines and adds events to the same candidate as the accepted fields.
Flutter supplies one UTC timestamp reused by preview and commit. Revision/digest
checks reject stale or altered proposals and repeated Save requests. The existing
private draft receipt/recovery flow is retained. Legacy/direct model creation,
edits and hierarchy copies do not masquerade as manual editor assignments.

`rank_tags` is a read-only application command. `AppController.rankedTags`
validates both current and returned working-copy identity and consumes only the
ranking, without applying its snapshot or occupying the mutation queue. The Rust
bridge serializes backend requests. Shared `ui/tag_selector.dart` renders the
ranked order, filters out selected tags, applies the stored suggestion limit and
guards nested picker results. It never calculates scores or invents defaults.

Existing schema-2 files need **no conversion or rewrite on open**. Missing
history means empty, and empty history is omitted from document serialization
and SQLite metadata. Existing items, tags, links, roots, views and preferences
are preserved; history is stored atomically after accepted operations. No
existing tag assignments are transformed, and schema-1 migration retains its
existing backup/validation gate. Future stored-data conversions still require
explicit migration plans. No app version, release or signing change is included.

## Verification and remaining acceptance

Rust tests cover decay, changed half-life, alphabetical ties, clock rollback,
invalid/atomic history updates, tag deletion, authoritative manual-vs-automatic
classification, failed/replayed saves, copy exclusion and frozen-file roundtrip.
Widget tests cover selected/suggested separation and limits, zero suggestions,
search/multi-select Done/Cancel, stale metadata/working-copy guards and constrained
layouts. Existing draft tests check cursor/composition stability and separate tag
creation. The native test opens a frozen distributed file, checks read-only byte
preservation, actual picker interaction, filter defaults, real Save/copy behavior,
decay, external rename/pending publication and restart/draft recovery. Windows
and Fedora native pipelines include that test.

Host verification on 2026-10-31 passed 109 Rust tests, 195 Flutter unit/widget
tests, Flutter analysis, 17 Python architecture/release checks, the new native
tag-picker integration and existing phone-layout/desktop integrations on Linux.
The ARM64 release APK built and passed both native ELF LOAD and APK ZIP 16 KB
alignment checks. These are host/build checks, not physical acceptance.

- [ ] Pixel/GrapheneOS and Samsung: verify real keyboard/search, touch selection,
  Done/Cancel/Back, main editor cancellation, popularity after accepted saves and
  process/lock/resume recovery using real document providers.
- [ ] Windows/Fedora: verify mouse/keyboard, scaling/short windows, copying and
  cross-platform transfer of settings/history without changing existing data.
- [ ] Upgrade the distributed app with real collections and exercise pending
  publication, external changes and recovery. Host checks do not establish
  physical acceptance.
