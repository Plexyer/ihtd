#!/usr/bin/env bash
# Package an already tested release bundle; build.sh runs this after validation.
set -euo pipefail
cd /workspace
rpm_root="$(mktemp -d /var/tmp/ihtd-rpm.XXXXXX)"
mkdir -p dist/fedora "$rpm_root"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp -a app/build/linux/x64/release/bundle "$rpm_root/SOURCES/IHTD"
cp packaging/fedora/dev.ihtd.app.desktop packaging/fedora/ihtd.svg "$rpm_root/SOURCES/"
rpmbuild -bb --define "_topdir $rpm_root" packaging/fedora/ihtd.spec
cp "$rpm_root"/RPMS/x86_64/*.rpm dist/fedora/
tar -czf dist/fedora/IHTD-0.2.0-fedora44-x86_64.tar.gz -C "$rpm_root/SOURCES" IHTD
cp packaging/fedora/INSTALL.md dist/fedora/INSTALL.md
cd dist/fedora
sha256sum *.rpm *.tar.gz > SHA256SUMS
