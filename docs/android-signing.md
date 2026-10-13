# Permanent Android signing

For the repository owner's step-by-step home-computer checklist, see
[`android-signing-home-setup.md`](android-signing-home-setup.md).

The permanent key identifies every public IHTD Android installation. Android
accepts an update only from that identity (or a deliberately configured signing
lineage). Never generate a replacement casually. The existing v0.2.1 APKs use
development keys; they cannot be updated by a newly established release key.

The owner-approved key has already been created in the cloud workspace and its
public certificate is pinned in source. Use that existing key and the home
backup steps below. The generation command is for initial setup of a new app,
not a step to repeat when restoring IHTD on another computer.

## Owner-controlled creation and backup

Install Python 3 and a JDK (Android Studio includes one), with `keytool` on PATH.
In your own private account directory on your PC, choose a keystore location
outside the repository, such as a private `IHTD signing` directory. Run from
the repository, replacing the example path with that private location:

```sh
python scripts/android-signing.py generate --keystore /private/path/ihtd-release.p12
```

The script prompts for a password twice without echoing it. Use a unique random
password of at least 20 characters, retained in your password manager. PKCS12
uses that same password for the keystore and private key. The alias is
`ihtd-release`. RSA 4096 and a 10000-day validity are used. Generation refuses
to replace existing files. Unix permissions are restricted; on Windows use a
directory accessible only by your account. Do not generate into a shared folder.

The script writes only the **public** certificate fingerprint into
`packaging/android/release-certificate.sha256`. Commit that fingerprint through
a reviewed PR; the encrypted keystore and password never belong in Git, chat,
collections, build artifacts, or release downloads.

Before activating releases, retain two encrypted copies of the keystore in
independent places, such as an offline drive and your encrypted backup system.
Keep the password separately. Test opening a restored copy with keytool and
confirm its certificate fingerprint. Retain the alias and document who owns
the backups and how they can be restored. GitHub Secrets is a build credential
store, not your only backup.

For owner-approved cloud creation, `generate --password-file <private-file>`
generates a random password into a new mode-0600 file instead of prompting.
Keep both files outside the repository in a private directory. The current
owner-approved key is in `/workspace/ihtd-private-signing/ihtd-release.p12`,
with its password in the separate `signing-password.txt` there. This cloud
workspace is not permanent backup storage. Download at home, put the password
in your password manager, retain independent encrypted backups, and test a
restore. File contents must never be pasted into chat or uploaded as artifacts.

## GitHub administrator setup

Create the environment **android-release** in Settings → Environments. Restrict
deployment to version tags matching `v*`; branches and pull requests must not
be permitted. Add reviewer approval if your GitHub plan supports it. Keep the
signing secrets in this environment, rather than broadly exposing them to
normal build jobs. If your private-repository plan cannot support this protected
environment, resolve that limitation before enabling public signing.

Add these three environment secrets:

| Secret | Value |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | Base64 of the encrypted .p12 file |
| ANDROID_KEYSTORE_PASSWORD | The password from your password manager |
| ANDROID_KEY_ALIAS | ihtd-release |

Use a trusted local GitHub CLI to upload them without pasting secrets into chat
or saving plaintext values in the repository:

```sh
python scripts/upload-android-signing.py --keystore /private/path/ihtd-release.p12
```

The uploader prompts for the password, validates the key against the committed
fingerprint, and sends values to `gh secret set` over stdin. It never writes
password/base64 files. Requires an administrator's GitHub login and an already
configured protected environment. The cloud integration credential currently
cannot access the repository's secret settings (HTTP 403).
For the generated cloud key, use `--password-file <downloaded-password-file>`
on your trusted home computer; no password needs to be pasted into a terminal.

## CI behavior and local signing

PR/manual branch builds produce development-signed test APKs. A tagged release
first validates the pinned public fingerprint, builds/tests a candidate without
the permanent key, then signs it in a separate protected environment job.
Only the signing step receives secrets. It aligns the APK, re-signs it, verifies
the single signer against the pinned fingerprint, checks 16 KB ZIP alignment,
and publishes `IHTD-X.Y.Z-android-arm64.apk` plus SIGNING-CERTIFICATE.sha256.
Temporary decoded key material is removed even when signing fails. Missing
configuration or a wrong certificate fails the release; debug-key fallback is
not permitted. Review tag code before granting the protected environment access.

For a trusted local build, set the same three variables temporarily in your
process and run `android-signing.py sign --apk <test-apk> --output <new-apk>`
with `--apksigner <SDK>/build-tools/36.0.0/apksigner` and the analogous
`--zipalign` path. Clear the variables afterward. Passwords are passed to tools
through environment references, never command-line values. The .p12 stays
encrypted outside Git; the public fingerprint stays in reviewed source.
Alternatively pass `--keystore <private.p12> --password-file <private-file>` to
the signing command. These file paths contain no secret values. The final
signature is still checked against the committed certificate.

## First migration and update test

1. Export collections from the old development app and verify the exports can
   be opened. Preserve important recovery edits before uninstalling.
2. Uninstall the old development-key app, install the first permanent-key APK,
   and reopen exported collections through Files. This one-time migration clears
   old private data and document grants; it cannot preserve an incompatible key.
3. Build a later APK with the **same** release key and a higher Android build
   code. Use a new public version/tag, never move v0.2.1 or replace its assets.
4. On the Pixel with default GrapheneOS settings, install that APK as an update
   without uninstalling. Verify edits, preferences, retained document grants,
   working copies, and recovery data survive lock/unlock and restart.

Certificate/build checks on a host do not prove preservation of real phone data.
Physical-device upgrade testing is required before marking signing complete.

Local verification produced `dist/signing-verification/IHTD-permanent-key-build5.apk`
and `IHTD-permanent-key-build6.apk`: same package ID/certificate, increasing build
codes, verified signatures and 16 KB ZIP alignment. They are migration/update
test packages, not replacements for the immutable v0.2.1 GitHub assets. A later
public release should use a new version/tag and a higher build code than any
test APK installed on the phone.
