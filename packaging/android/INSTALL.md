# IHTD @VERSION@ test APK for Pixel 9 Pro / GrapheneOS

Requires ARM64 and Android 15/API 35 or newer. Transfer
`IHTD-@VERSION@-android-arm64-test.apk` to the phone and open it in Files. Allow
APK installation for that source when Android prompts, then open IHTD.
Keep GrapheneOS protections enabled. Core operation needs neither Google Play
services nor internet permission.

Start with a new test collection in local Files. Open a copy of important
desktop documents for the first test. IHTD uses scoped document grants and keeps
a private working copy; edits are published to the selected file with readback
verification. On an external-change conflict, use Save a copy as before reopening.
Provider confirmation does not guarantee that a sync provider uploaded the file.
Edit a collection on one device at a time.

This APK uses a development key. A build from another workspace or GitHub runner
may use a different key and cannot update an existing installation. Export all
collections before uninstalling or clearing data. Durable release signing is
still pending. The locally built APK in this cloud workspace retains the same
development key as the earlier APKs supplied in this chat.

Check installation, document creation/opening/export, screen lock and restart,
keyboard/back navigation, long-press moves and external-change recovery on the
actual phone. Host build/tests cannot replace these device checks.
