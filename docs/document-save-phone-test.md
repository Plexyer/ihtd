# Pixel document-saving acceptance test

Use disposable copies and the permanent-key candidate IHTD 0.2.2 build 7.
Install it as an update over permanent-key build 5/6 without uninstalling.
Back up important .ihtd files first. This is a test candidate, not a published
stable release. Automated provider fakes cannot verify the actual Files provider.

Candidate filename: `IHTD-0.2.2-build7-android-arm64-test.apk`.
SHA-256: `c329c07bbea28fce26c95aa5a6660981c574f44807c3cef228cc020bdeec2412`.
The candidate was built from implementation commit `340c46e` (including the
versioned source), with packaging metadata aligned in `c9462f9`. Its permanent
certificate, ARM64-only packaging, API 35 minimum/API 36 target, ZIP alignment
and all four native libraries' 16 KB-or-greater ELF load alignment were verified.
APK permissions contain no internet or broad-storage grants.

## Rename and pending changes

1. Create/open Tasks_copy.ihtd and add recognizable tasks; confirm Saved to file.
2. Background IHTD, rename the file to Tasks_copy_copy.ihtd in Files, and return.
3. Expect a yellow warning (within a foreground check). Tap it: the explanation
   should identify the old/new names and unchanged contents if the retained URI
   still works. If that provider invalidates the URI, expect a conservative
   unavailable-access explanation instead, not a fabricated rename diagnosis.
4. Make an edit. Expect yellow Pending changes — not saved to file. Verify the
   renamed external document's bytes/content have not received the edit.
5. Open the task, change views, open/dismiss the popup and wait for several checks.
   The warning and pending edits must remain; these actions must not publish.
6. Lock/unlock and restart IHTD without clearing app data. Verify the retained
   edits and confirmation barrier survive. Do not uninstall during this test.
7. Use Confirm renamed file, or Select file to reconnect if the old URI fails.
   Read the named destination confirmation and cancel once; nothing should save.
8. Confirm the intended destination. Expect a verified save and updated filename;
   reopen the external document to verify the exact edits reached it.

## External content changes and switching

1. While IHTD has a copy open, modify the external document using another editing
   instance/tool, with only one instance writing at a time. A duplicate file with
   a similar name is not the same test as changing the selected document.
2. Verify a yellow external-change warning; if also renamed, the explanation
   should mention both facts when available. Add local edits; IHTD must not
   overwrite the external changes, including through Retry/Confirm.
3. Use Save a copy to a new file and verify the latest locally accepted edits.
4. Alternatively use Open external version. Confirm preservation of local work,
   select the external file, and verify it opens without receiving old edits.
5. In File connection and saving → Advanced details → Retained working copies,
   reopen the former local copy. Verify its edits survived and publishing stays
   blocked until a valid destination is explicitly confirmed.
6. Cancel the picker and select an invalid/corrupt document once. The existing
   active collection and recoveries must remain intact.

## Lost access and failed saves

1. Move/delete a disposable selected file or revoke its document access. Return
   to IHTD: expect a yellow access warning and local pending edits after editing.
   The message must not claim deletion when the provider only reports failure.
2. Restore access or explicitly select the intended file. Confirmation is still
   required; name alone must not automatically reconnect a replacement.
3. If possible, use a provider/test fixture that refuses writes or read-back
   verification while reading remains available. Expect red, no repeated
   automatic writes, retained local work, and retry/save-copy choices.
4. A genuinely full/private-storage failure should be red and must not promise
   verified local recovery. Do not intentionally fill a daily-use phone; use
   automated fault tests or a disposable test device for this case.
5. Repeat background/restart/offline operation. Verify core operation without
   Google Play services, broad storage permissions, or network access.

## Dialogs and logs

1. Tap each warning/error; verify readable explanation/actions with large text,
   portrait/landscape, keyboard shown/hidden and touch scrolling.
2. Expand Advanced details and export the default diagnostic JSON via Files.
   Verify it excludes filenames, paths, URIs, task titles/notes/contents and raw
   error messages. It should contain version/API, event codes, state and anonymous
   copy references. Export cancellation must leave document state unchanged.
3. Enable additional information. A separate confirmation explains the fields;
   cancel once, then export with consent. Only file names and provider metadata
   are added; full document URIs, contents and credentials remain excluded.
4. Share only a reviewed diagnostic file when reporting failures; report the
   exact steps and displayed status. Never send the signing key/password.

Record pass/fail per section and the installed Android/provider version. Stable
Android publication remains blocked until physical acceptance passes. Keeping
working/recovery files is not a substitute for external backups; clearing app
data or uninstalling removes private copies and diagnostic logs.
