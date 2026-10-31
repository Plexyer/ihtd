# Fedora 44 x86-64 packaging

The 0.2.1 branch rebuilds the shared Android/desktop changes in a disposable
Fedora 44 container. The historical verification below describes 0.2.0.
Current build results are recorded in `docs/release-0.2.1.md`.

Built and validated on 2026-10-07 in Fedora 44 under WSL 3.0.1.
Artifacts are in `dist/fedora`; see [installation instructions](INSTALL.md).
All 47 Rust tests, Flutter analysis, and Linux UI integration test passed.
The RPM was installed, its file integrity and shared libraries checked, and
the release stayed running for 15 seconds as an ordinary Linux user under Xvfb.
Wayland, display scaling, native file picking, and rclone on the physical laptop
still need checking.

The build installs the official Flutter 3.47.5 Linux SDK, verifies its published
SHA-256, installs Rust 1.93.1, and builds on Fedora 44. It runs the Rust tests,
Flutter analysis, and Linux integration test under a virtual X display before
building the release. Outputs are an RPM with an application-menu entry and a
portable tar.gz bundle. Real Fedora laptop testing is still required afterward.

With a working Docker Linux engine, run these commands from the repository root:

```
docker build -f packaging/fedora/Dockerfile -t ihtd-fedora-builder .
docker run -e IHTD_DISPOSABLE_FEDORA=1 -e IHTD_SOURCE_REVISION="$(git rev-parse HEAD)" --name ihtd-fedora-package ihtd-fedora-builder
docker cp ihtd-fedora-package:/workspace/dist/fedora ./dist/fedora
```

Use an unused container name if repeating the build. Downloads and toolchains
require several GB of disk space. The build image contains development tools;
the resulting RPM and portable bundle do not require Flutter or Rust to run.

After a successful build, on the Fedora laptop:

```
sudo dnf install ./ihtd-0.2.1-1.fc44.x86_64.rpm
```

Launch IHTD from the application menu, then open the existing .ihtd document
through its file picker. An rclone-mounted folder works as an ordinary path.

## WSL build environment

The dedicated `IHTD-Fedora44` WSL distribution contains the source in `/workspace`
and the installed toolchains. Its official Fedora image was checksum-verified
before import. Updating WSL from 2.4.11 to 3.0.1 fixed `Wsl/Service/E_UNEXPECTED`.
Docker was not needed for the successful build.

After copying current source into `/workspace`, run inside that distribution:

```
bash /workspace/packaging/fedora/build.sh > /workspace/fedora-build.log 2>&1
# Current upgrade/removal verification requires a disposable Docker/Podman container.
```

For a fresh dedicated Fedora environment, copy the source to `/workspace` and
run `bash /workspace/packaging/fedora/setup.sh` as root before those commands.
Setup installs compiler dependencies, Flutter, and Rust; verification installs
the RPM and creates an isolated `ihtd-smoke` account. These scripts are intended
for a disposable build environment, not the everyday laptop account.

`package.sh` can repeat packaging of an already tested release bundle without
recompiling. Staging uses a fresh `/var/tmp` directory for each run. Keep logs
under `/workspace`; the WSL distribution clears `/tmp` between starts.

The Docker recipe uses the same setup/build scripts, but the Docker engine on
this host still has its separate `dockerInference` startup issue. The Docker
route itself was not exercised. No Docker reset or security changes were made.

The user's usage constraint remains: stop before the five-hour allowance has
less than 10% remaining. Do not consume a usage-reset credit.

References:
- Fedora release: https://www.fedoraproject.org/workstation/download/
- Flutter Linux requirements: https://docs.flutter.dev/platform-integration/linux/setup
- SDK checksums: https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json

## Current released-version verification

`verify.sh` now requires both a container and `IHTD_DISPOSABLE_FEDORA=1`.
The coordinated CI container explicitly runs build.sh then verify.sh. The
verifier downloads the actual published v0.2.5 RPM, pinned by size/SHA-256,
launches it with its historical synthetic document, upgrades to the candidate,
and checks external/private collection bytes through launch, uninstall and
reinstall. These installs/removals must never run on an everyday workstation.
The default Docker CMD only builds; for verification pass the same command as
CI: `bash -c 'bash packaging/fedora/build.sh && bash packaging/fedora/verify.sh'`.
See [upgrade acceptance](../../docs/upgrade-acceptance.md) for physical checks.
