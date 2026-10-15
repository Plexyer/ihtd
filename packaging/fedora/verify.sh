#!/usr/bin/env bash
# Run inside the disposable Fedora build environment after build.sh.
set -euo pipefail
cd /workspace
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' app/pubspec.yaml)"
dnf install -y "./dist/fedora/ihtd-$version-1.fc44.x86_64.rpm"
rpm -V ihtd
for notice in /opt/ihtd/LICENSE /opt/ihtd/COPYRIGHT /opt/ihtd/SOURCE.txt /usr/share/licenses/ihtd/LICENSE; do
  [[ -s "$notice" ]] || { printf 'Missing license/source notice: %s\n' "$notice" >&2; exit 1; }
done
[[ "$(rpm -q --queryformat '%{LICENSE}' ihtd)" == 'AGPL-3.0-only' ]]
for binary in /opt/ihtd/ihtd /opt/ihtd/lib/*.so; do
  dependencies="$(ldd "$binary")"
  if [[ "$dependencies" == *"not found"* ]]; then
    printf 'Missing dependency in %s:\n%s\n' "$binary" "$dependencies" >&2
    exit 1
  fi
done

# Use an ordinary account to catch permissions problems in the installed RPM.
id ihtd-smoke >/dev/null 2>&1 || useradd --create-home ihtd-smoke
runtime_dir="$(mktemp -d /var/tmp/ihtd-smoke.XXXXXX)"
chown ihtd-smoke:ihtd-smoke "$runtime_dir"
set +e
runuser -u ihtd-smoke -- env XDG_RUNTIME_DIR="$runtime_dir" GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
  dbus-run-session -- xvfb-run -a timeout 15s /usr/bin/ihtd \
  > /workspace/fedora-release-smoke.log 2>&1
result=$?
set -e
cat /workspace/fedora-release-smoke.log
if [[ "$result" != 124 ]]; then
  printf 'Release exited early (status %s).\n' "$result" >&2
  exit 1
fi
printf '%s\n' 'Installed RPM verified; release remained running for 15 seconds as an ordinary user.'
