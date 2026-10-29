# Unlink/Delete acceptance

Historical baseline: the later [link/copy/removal contract](link-copy-removal.md)
supersedes the either-Unlink-or-Delete actions and direct-placement counter here.
Use its explicit global Delete, appearance counts and blocked-Unlink safeguards.

Use a disposable test collection on Pixel 9 Pro / GrapheneOS, Windows 11 and
Fedora. Implementation is shared; physical checks remain pending. Build 10
contains these changes. Install the signed build 10 over the existing permanently
signed app without uninstalling; collection/recovery/grant preservation still
needs the physical checks. Do not use important collections for destructive tests.

1. Create a root task and a root folder. Their row menus and details placement
   actions say **Delete**. Cancel confirmation: nothing changes or saves. Confirm:
   the item disappears, including after reopening the collection.
2. Create parent folders A and B. Put task T under A and link it under B. Each
   occurrence offers **Unlink**. Unlink T from A: no confirmation, T survives
   under B with the same ID, notes, tags and children. B's occurrence now offers
   **Delete**. Repeat with a shared folder.
3. Create an explicit top-level placement while retaining a parent link (link
   under A and B, then move A's placement to the top level). The details panel
   lists both Top level and B. Unlink either placement: the other survives.
   Reopen and verify neither placement was recreated accidentally.
4. Create Trip with unique child Pack and shared child Book, also under B. Give
   Pack and Book their own children. Delete Trip: confirmation identifies deleted
   items and retained branches. Trip, Pack and Pack's unshared descendants are
   removed; Book and its children survive under B. Children with explicit roots
   also survive. A descendant whose only parents are both deleted does not survive.
5. Link folder F under A and B, with child C only under F. C appears twice but
   has one actual placement. Its action says Delete. Confirming removes C from
   both appearances; F remains in both places. The dialog explains shared-parent
   effects. Filtered views do not increase placement counts.
6. Create an automatically completing parent with one finished and one unfinished
   child. Delete the unfinished child: completion/inheritance recalculates.
7. Create a saved view with an Inside Trip rule, including nested AND/OR/NOT
   examples. Delete Trip: the view stays, receives a yellow shade, and shows a
   small warning above its hierarchy with the rule position and container ID.
   Tap it: the editor shows Deleted container. That rule matches nothing;
   other Boolean rules keep their existing semantics. Replace/remove the rule:
   the yellow warning clears. Reopen to verify warnings and repairs persist.
8. Leave a Delete dialog open and change the document through another available
   action, or switch collection. Approval must fail safely. Retry obtains a fresh
   preview/confirmation; a stale Unlink can never silently become Delete.
9. Edit a title immediately before removing a placement. Valid drafts flush before
   preview; invalid drafts block removal. Deleted selection clears, surviving
   selection remains, and removed paths do not leave broken expansion state.
10. Rename/move the external file or revoke provider access. Unlink/Delete still
    edits the retained private copy; the external file stays unchanged and the
    existing yellow pending warning remains. Confirm reconnection to the unchanged
    baseline: the approved result publishes and survives reopening. Restart while
    pending and verify retention. Other collections/copies remain unchanged.
11. Check row menus, details choices, preview scrolling and Cancel/Delete on the
    phone with keyboard open/closed, portrait/landscape and large text. Check
    mouse/keyboard and smaller desktop windows. Shared-parent removal should not
    require platform-specific actions.

Existing schema-1/2 collections open without deleted-ID metadata. New saves keep
optional `deleted_item_ids` metadata and JSON exports include it; this preserves
missing-container rules without retaining deleted item contents. Older app builds
that reject missing filter containers cannot open a new collection containing
such a rule until it is repaired using build 10 or later.

Automated verification is recorded in the implementation plan/checklist; passing
host/native tests does not mark these physical checks complete. Merge through
`development`; no stable release or new version tag is created by this task.
