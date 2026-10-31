# 0.3.0 upgrade acceptance

Candidate: **0.3.0, Android build 15**. Baseline: published **0.2.5, build 14**.
This is step 12 in the [implementation order](FEATURE_CHECKLIST.md#implementation-order).
All feature implementations are candidates; physical results must be recorded,
not inferred from CI. Use [the result sheet](upgrade-acceptance-results.md).

## Getting a usable candidate

1. Review/merge the acceptance task into `development`. The draft release PR
   targets `master` from `release/0.3.0` and runs the existing full validation:
   Android, Windows and Fedora builds plus native tests/package verification.
2. After review and green checks, merge the release PR into `master`. Tag that
   reviewed master commit `v0.3.0` using the normal release process. The tag run
   signs Android with the permanent key and creates a complete draft prerelease.
3. Review all draft assets, signing certificate/checksums and notes. For phone
   testing, publish it **with Prerelease still checked**, without making it latest.
   This makes direct asset downloads available while the stable updater continues
   to exclude the candidate. Do not promote it to stable until acceptance passes.
4. Download the platform package and `IHTD-0.3.0-upgrade-tests.zip` from that release.
   Extract the test ZIP using Files/My Files/Explorer. Follow its README.

The branch/PR Android `*-test.apk` uses a test key. Android will reject it as an
in-place update over permanent-key installations. Use the permanently signed
`IHTD-0.3.0-android-arm64.apk` from the tag run for the two phones. Keep the installed
app/data in place; signing failures must be investigated, not worked around by
uninstalling. The stable certificate is recorded in `SIGNING-CERTIFICATE.sha256`.

The test ZIP contains only synthetic data, instructions and a result sheet. Its
four files were generated with the real v0.2.5 model/storage crates at pinned
commit `ec7144a6a03dc666e3fad885e1fe1562cf144569`; each reopens in that old library.
The files deliberately share a UUID, while their file/working identities stay
separate. Opening the working-snapshot fixture is an ordinary explicit file open,
not automatic restoration of another file's private pending edits.

## Before installing on either phone

Record phone model, OS/Android/API, installed app version/build and candidate
filename. Pixel 9 Pro/GrapheneOS and the father's Samsung are separate test rows.
Both require ARM64 and Android 15/API 35 or newer. Record actual versions rather
than installing an older APK to force a particular baseline.

1. In the current app, save normal work and check the file status. For pending
   local work, use Save a copy/export to preserve the latest working contents.
   Keep a separate copy of important collection files using Files/My Files.
2. Start with copies of the numbered synthetic test files, separate from real
   collections. Record where they are stored and any sync/document provider.
3. Open the permanently signed candidate APK from Downloads. Android/GrapheneOS
   supplies source permission and the update confirmation. Approve the update;
   use its normal Open action when finished. No uninstall or app-data reset.
4. Verify the app identity/new icon, version/build, previous collection access and
   any pending work. A different-key/package or failed installation stops this
   test; retain files and record the exact OS message.

## Core upgrade and migration checks

Run these on both phones, Windows 11 and Fedora 44 where available:

| Case | Action | Expected result |
| --- | --- | --- |
| Intact default | Open `01-intact-default.ihtd` | All tasks is protected; no unnecessary conversion/backup-folder request |
| Customized default | Open a copy of `02-customized-default.ihtd` | Verified pre-upgrade backup; fresh protected All tasks; old customized view remains unchanged |
| Deleted default | Open a copy of `03-deleted-default.ihtd` | Verified backup and restored protected All tasks; all remaining views/data preserved |
| Working snapshot | Open `04-unpublished-working-snapshot.ihtd` separately | Example unpublished passport edits remain; other numbered files are untouched |
| Backup refusal | On a fresh customized-file copy, cancel/deny a required backup-folder selection | Conversion stops; original data stays intact; upgrade details explain the next step |
| Backup/read/write failure | Use disposable data and an unavailable/read-only provider or failed backup destination | Upgrade/save stops safely; pending data is retained; diagnostics are available |

Android may need one-time backup-folder selection. Existing authorization can
make the prompt unnecessary; record that rather than reporting a failed refusal
case. Use another authorized destination when needed. Verify backup contents
before applying any manual cleanup; keep the original fixture copies as references.

The old data includes Japan trip/Home with the same passport task in both,
Japanese/multiline notes, dates, all three priorities, nested packing, an automatic
completed parent/child, custom filter/preferences and a deleted-container rule.
Check all of them. The retained deleted-container view should carry its minor
warning; its invalid rule should remain editable, not disappear silently.

## Changes to exercise together

- Edit a task and a folder: typing stays private; Save closes; Cancel discards.
  Back/Escape and switching with changes offer Save/Discard/Keep editing. Check
  cursor position/composing text with your normal keyboard. Background, lock and
  return; on disposable drafts test process restart and restore/discard.
- Open the keyboard/landscape or a short desktop window during creation. Top
  Create remains accessible and bottom Create is retained. Blank titles/failed
  saves retain the draft; one valid submission creates one item.
- Check passport `Links: 2`, shared completion and both appearances. Link/Copy
  search, copy-depth choices and shared/internal versus independent copies work.
  Unlink is local; Delete explains its global effect. Blocked child Unlink offers
  the documented independent-parent replacement, preserving originals elsewhere.
- Change sorting per view/parent. Drag from an automatic order; verify the visible
  order becomes Manual and hidden siblings keep their slots. Moving out of a
  shared parent is blocked with the copy explanation.
- Change collection/parent/view indicator settings and reset individual overrides.
  Direct-child summaries follow view rules/current tab; the completed/total ratio
  spans tabs. Total/next date share the footer; enabled nonzero priorities form the
  centered stack. Next date ignores overdue dates and disappears when none qualify.
- Select multiple tags through search: Done stages, Cancel discards picker changes.
  Item Cancel discards assignments while keeping a separately created tag. Old
  assignments start without usage history; accepted manual additions affect rank.
- Verify the new logo in the header/About, installed icons and startup. Check
  themed/adaptive Android icons, OS dark mode, large text and short windows. Startup
  has no artificial pause. Update-indicator space stays beside the top-right menu.

## Disconnection, pending saves and restart

1. With a disposable collection open, minimize IHTD and rename that file in Files
   or Explorer; return. A provider may report the new name or only lost access.
   Expect a yellow warning based on the facts available, with clickable details.
2. Edit a note and press Save. The app retains the accepted change locally and
   reports pending file saving. The renamed external file must not be overwritten
   through an unconfirmed different destination or falsely reported as saved.
3. Make another unfinished note edit, background the app and allow its private
   checkpoint to finish. Restart/force-stop the disposable test process and reopen.
   Verify accepted local changes plus the separately offered unfinished draft.
   Restore/discard explicitly; no private edit may overwrite another file just
   because its collection UUID matches.
4. Reconnect by explicitly selecting the renamed file and reviewing its identity/
   content information. Confirm only the intended destination. Verify accepted
   pending edits publish and read back, while discarded draft fields stay absent.
5. Repeat with an externally changed/replaced file and a revoked provider grant.
   Warnings must preserve work and require review. Actual write/verification or
   private-persistence failures use red errors; retain logs/recovery before retry.

For an upgrade failure, open its details and export the automatically retained
redacted log. Record the stage/result and synthetic filename used. Default logs
can be shared for debugging; personal collections are separate content-bearing
files and are not required for a synthetic reproduction.

## Windows and Fedora installation

CI exercises the actual pinned published 0.2.5 Windows installer/RPM, upgrades to
the candidate and checks retained external/private data. Installation/removal
runs only on disposable runners/containers. The real laptop/PC checks remain:

- Windows 11: install over the current app, retain install directory/shortcuts/
  file association, launch a collection from Explorer and reopen from another
  working directory. Verify app/window/installer branding and existing data.
- Fedora 44: upgrade the RPM, verify desktop/file-picker integration, Wayland,
  display scaling and the real rclone/document mount. Record signed/unsigned
  package status; desktop updates still use manual release-page installation.

## Publication and updater acceptance

Keep the candidate a prerelease during this testing. The production updater must
ignore drafts/prereleases. A manually installed 0.3.0 candidate correctly receives
no update offer for that same version or older stable 0.2.5.

The owner previously reported successful v0.2.5 update checks on both phones after
enabling network permission. That is historical evidence, not a result for this
candidate's new layout/draft behavior. Record any new end-to-end updater run when
a genuinely later stable release exists; do not publish a dummy stable release
merely to force an icon. Shared update/installation-preparation tests cover the
new draft barriers and indicator states in the meantime.

Promote the reviewed prerelease to stable/latest only after critical physical
upgrade/data checks pass. Keep the exact tested tag/commit/assets; fixes require
an updated candidate and increasing Android build. Keep pre-upgrade backups:
old apps can drop new metadata if used to edit upgraded files. Restoring a backup
is distinct from downgrading/reinstalling the app or clearing its private data.
