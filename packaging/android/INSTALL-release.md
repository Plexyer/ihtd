# IHTD @VERSION@ for Pixel 9 Pro / GrapheneOS

Requires ARM64 and Android 15/API 35+. Download
`IHTD-@VERSION@-android-arm64.apk` and open it in Files. Approve installation
through Android's package installer. Google Play services are unnecessary.

This APK is signed by the permanent IHTD release key. SIGNING-CERTIFICATE.sha256
records its public certificate fingerprint. Future releases with this same
certificate and a higher Android version code can update it without uninstalling.

Earlier development-signed builds, including v0.2.1 test APKs, use different
keys. Export and verify your collections outside IHTD's private storage before
uninstalling an old test build to switch signing identities. Uninstalling clears
private working copies, recovery data, and retained document access.

After the first permanent-key installation, verify document creation/opening,
editing, lock/unlock, restart and updating on the physical Pixel. Continue editing
each collection on only one device at a time. Save a copy when file access or an
external-change conflict prevents publication.
