# Windows packaging

Windows 11 x64 is the product target. Native CI runs on Windows Server 2022.
The package consists of an Inno Setup installer and a complete portable ZIP,
both generated from the same Flutter release bundle.

## Build

Install the pinned Flutter/Rust toolchains and Visual Studio C++ workload as
described in [building](../../docs/building.md). Install the verified Inno Setup
6.4.3 compiler once:

```powershell
./scripts/install-inno-setup.ps1
$env:IHTD_ISCC = Join-Path $env:LOCALAPPDATA 'IHTD-BuildTools\InnoSetup-6.4.3\ISCC.exe'
./scripts/build-windows.ps1
./scripts/package-windows.ps1
```

The compiler download is pinned by SHA-256 and its Authenticode signature must
be valid. An existing Inno Setup 6.4.3 or later 6.x compiler can be selected with
`-CompilerPath` on the packaging script. Microsoft redistributable CRT DLLs
come from the installed Visual Studio `VC/Redist/MSVC` x64 directory and are
bundled app-locally. Use a properly licensed Visual Studio installation and
follow Microsoft's redistribution terms. Never copy runtime DLLs from random
download sites or from System32.

Package output goes into `dist/windows`:

- `IHTD-X.Y.Z-windows-x64-setup.exe`
- `IHTD-X.Y.Z-windows-x64.zip`
- `INSTALL.md`
- `SHA256SUMS` covering both packages

Packaging refuses to reuse its staging directory. Move an existing
`dist/windows` output aside before repeating the build. `app/pubspec.yaml` is
the shared version source; do not edit version numbers inside the installer.

## Upgrade and data contract

The installer is per-user, with no elevation, and uses a permanent AppId:
`{E216F57E-504E-43AB-8536-FC8509C1A40D}`. Never change that identity between
versions. Inno Setup retains the chosen installation directory and tasks on
upgrade. The default destination is `%LOCALAPPDATA%\Programs\IHTD`.

Start Menu integration is always installed. The desktop shortcut is optional
and unselected on first installation. File registration is optional and
selected on first installation. Registration is under HKCU using
`IHTD.Collection` and `.ihtd\OpenWithProgids`; it respects Windows UserChoice
and an existing default handler. The open command quotes the executable and
document separately. Flutter receives the document path at startup and opens
it through the normal validated storage command, displaying errors normally.
Each invocation currently starts a separate window.

Collections stay where users save them. The existing application support
identity (`dev.ihtd` / `IHTD`) is kept stable; Windows recovery data is normally
in `%APPDATA%\dev.ihtd\IHTD\recovery`. Upgrade and uninstall must never delete
this directory or user collections. There are no wildcard cleanup rules for
the installation directory; uninstall removes its recorded installed files,
registration and shortcuts, leaving files added by the user. Close IHTD after
saving before replacing its files. Restart Manager can ask to close running
processes, but the installer does not automatically restart IHTD.

## Verification

The Windows build workflow supports a manual dispatch for a single-platform
check, as well as calls from coordinated release validation. On a disposable
Windows runner it builds/tests the app, compiles both packages and runs
`scripts/verify-windows-installer.ps1`. The script refuses everyday local runs
because it installs/uninstalls software and changes the user's registrations.
It checks:

- identical portable and installed payloads, including runtime DLLs;
- the actual published v0.2.5 installer upgrading in the same directory, retaining tasks;
- Start Menu/desktop shortcut targets and quoted document registration;
- installed and portable app launch and normal close from another directory;
- preserved real collection and recovery bytes after upgrade/uninstall; and
- removal of registration/shortcuts and reinstall with optional tasks omitted.

The baseline is the actual published v0.2.5 EXE, pinned by exact size/SHA-256
in `packaging/upgrade-baseline.json`. The baseline app opens synthetic documents
written by its own historical storage library. Shared native tests separately
verify full document preservation, guarded migration and recovery across the
candidate's feature changes. Physical Windows 11 Explorer/default-app and interactive wizard
checks remain necessary before declaring the installer ready for public use.

Historical verification of the previous synthetic-installer baseline passed on 2026-10-13 in
[Windows run 38405384372](https://github.com/Plexyer/ihtd/actions/runs/38405384372).
Both UI scenarios, installer compilation, every installer check above and
artifact upload passed. Its `windows-package` artifact contains the setup EXE,
portable ZIP, rendered installation guide and two-package checksums; retention
is 14 days. This is a task-branch test build, not a new published version.

For a physical Windows 11 test, use backed-up sample collections: install,
choose shortcuts, set IHTD as the default if desired, open a collection through
Explorer, edit/save, upgrade to a newer package, reopen and compare data, then
uninstall and confirm collection/recovery retention. Also try no optional
tasks and opening a missing or invalid document, which must show a useful error.

Packages are currently unsigned. Authenticode signing and any automatic
download/execution are separate pending tasks. Do not publish a stable release
or replace old tag assets just to test this installer.
