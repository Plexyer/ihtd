# Android signing: owner setup at home

Use this checklist on the repository owner's trusted home computer. It connects
the existing permanent IHTD Android signing key to GitHub Actions. Do **not**
generate another key: Android treats a different key as a different publisher,
and applications signed with it cannot update existing installations.

No private key, password, or Base64-encoded key belongs in Git, GitHub release
assets, issue/PR comments, IHTD collections, email, or chat.

## 1. Create the protected GitHub environment

This part can be completed before downloading the key:

1. Open the `Plexyer/ihtd` repository on GitHub.
2. Open **Settings → Environments**.
3. Select **New environment**.
4. Name it exactly `android-release`.
5. Under **Deployment branches and tags**, choose **Selected branches and
   tags**.
6. Add the tag pattern `v*`.
7. Do not allow ordinary branches or pull requests.

If the GitHub plan offers required reviewers, reviewer approval may be added so
that signing waits for manual approval. A sole maintainer should not enable
**Prevent self-review**, because that can make their own release impossible to
approve. If the private-repository plan does not support the required
protection, resolve that before enabling public signing.

## 2. Recover and protect the existing key

Download these two files from the private cloud workspace through the original
Codex conversation:

- `IHTD-Android-Signing-Key.zip`
- `signing-password.txt`

Extract `ihtd-release.p12` from the ZIP. The ZIP itself is not encrypted; the
PKCS12 keystore inside it is encrypted with the separate password. Then:

- save the password in a password manager;
- retain at least two independent backups of `ihtd-release.p12`, such as an
  offline drive and an encrypted backup system;
- keep the password separate from the keystore backups;
- keep the alias `ihtd-release` in the recovery record; and
- never rely on GitHub Secrets or the cloud workspace as the only backup.

If the original files can no longer be downloaded, stop and recover the
existing key rather than generating a replacement.

## 3. Prepare the trusted computer

Install:

- Git;
- Python 3;
- GitHub CLI (`gh`); and
- a JDK containing `keytool` (Android Studio includes a suitable JDK).

Authenticate GitHub CLI as a repository administrator:

```sh
gh auth login
```

After the permanent-signing PR has been merged into `master`, clone or update
the repository:

```sh
git clone https://github.com/Plexyer/ihtd.git
cd ihtd
git switch master
git pull
```

For an existing clone, omit the `git clone` command and run the remaining three
commands from that clone.

## 4. Validate and upload the secrets

Run the repository uploader with paths to the recovered private files. On
Windows PowerShell:

```powershell
python scripts/upload-android-signing.py --keystore "C:\private\IHTD signing\ihtd-release.p12" --password-file "C:\private\IHTD signing\signing-password.txt"
```

On Fedora or another Unix-like system:

```sh
python scripts/upload-android-signing.py \
  --keystore "/private/path/IHTD signing/ihtd-release.p12" \
  --password-file "/private/path/IHTD signing/signing-password.txt"
```

Replace the example paths with the real private paths. The uploader verifies
that the certificate matches the fingerprint committed to the repository, then
sends the values to the `android-release` environment over standard input. It
does not print the password or create a plaintext Base64 file.

The resulting environment must contain these three secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS` (value: `ihtd-release`)

Confirm only the secret **names** under **Settings → Environments →
android-release → Environment secrets**. GitHub intentionally does not reveal
the values after upload.

## 5. Do not release yet

Secret presence does not complete signing validation. Before publishing a new
release:

1. Merge the permanent-signing changes through the normal review flow.
2. Complete the permanent-key migration and same-key update test on the Pixel
   9 Pro with GrapheneOS, preserving/exporting collections first.
3. Create a new version and tag with an Android build code higher than every
   test APK installed on the phone.
4. Review and approve the protected signing job if reviewer protection is
   enabled.
5. Verify the draft release before publishing it.

Do not replace the existing `v0.2.1` assets. Its Android test APK was signed
with a development key. The first public permanent-key build must use a new
version, expected to be `v0.2.2` or later.

For implementation details, recovery checks, and the Pixel migration test, see
[`android-signing.md`](android-signing.md).
