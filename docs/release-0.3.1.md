# IHTD 0.3.1 (build 16)

The owner requested this as a **stable Latest release**, including testing the
in-app updater from the manually installed permanent-key 0.3.0+15. This is a
real feature/fix release; keep v0.3.0 and its assets unchanged.

## Changes since 0.3.0

- Sorting now calls the existing title mode **Alphabetic**; saved preferences
  and ordering behavior remain compatible.
- Parents show a compact count of direct child tasks hidden by view rules,
  even with Total disabled. Tapping explains the filtering and offers guarded
  navigation to the parent in All tasks. Existing filtered totals and card
  alignment remain; visible ancestor-context tasks are not labeled hidden.
- Restyled shared task/folder editors follow the approved mockup: titled rules,
  outlined fields, clearer grouping and spacing, blue controls, and responsive
  date/priority fields. Save/Cancel, drafts, recovery and existing actions remain.
- Empty settings sections are hidden; childless folders retain applicable
  visibility controls.

These changes introduce no collection-format migration. Previously applicable
migration/backup gates remain active when opening older files that need them.

## Release procedure

1. Merge the version/notes task into development. Review the release/0.3.1 PR
   to master and require successful full Android/Windows/Fedora validation.
2. Merge the reviewed release PR into master. Tag that master commit v0.3.1;
   never tag an unmerged candidate or replace an existing distributed tag.
3. The tag workflow rebuilds, permanently signs Android and creates the normal
   draft prerelease with complete packages, update.json and checksums.
4. Review the signing result, manifest/version/build and all assets. The owner
   has authorized publishing **stable, with Latest enabled**: clear Prerelease
   and publish as Latest after verification. Keep the draft gate in CI intact.
   This choice supersedes the older 0.3.0 prerelease-only acceptance guidance
   for this release; do not invent physical acceptance results.

## Test the update button

On the phone keep the existing **0.3.0+15** installed until 0.3.1 is published.
Manually installing 0.3.1 first would remove the higher-version update offer.

1. Ensure IHTD has network access, including GrapheneOS's per-app permission.
2. Use the top-right menu's Check for updates action. Automatic discovery may
   wait for the normal daily interval; the manual action checks immediately.
3. Confirm the blue download icon beside the menu offers version 0.3.1.
4. Open it, review/confirm the download, and check the animated progress state.
5. When verification completes, the icon becomes a green tick. Tap it and use
   Android's normal source-permission/installation confirmation; keep app data
   installed. Do not uninstall or clear data.
6. Reopen IHTD, verify version 0.3.1+16, existing collection access, accepted
   edits and retained private drafts/recovery. The update icon should disappear.
7. Record actual device results and export redacted diagnostics for any failure.
   Preserve independent copies of important collections before testing upgrades.

The APK retains the pinned permanent signing identity. Windows/Fedora updates
continue to use the release page/manual installation for unsigned packages.
Physical phone/desktop visual and updater acceptance is pending owner testing.
