#!/usr/bin/env bash
# Only inside the disposable Fedora build container after build.sh.
set -euo pipefail
if [[ "${IHTD_DISPOSABLE_FEDORA:-}" != 1 || ( ! -e /.dockerenv && ! -e /run/.containerenv ) ]]; then
  printf '%s\n' 'Run upgrade/removal verification only in the disposable Fedora container.' >&2
  exit 1
fi
cd /workspace
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' app/pubspec.yaml)"
python3 scripts/download-upgrade-baseline.py --platform fedora --output /var/tmp/ihtd-upgrade-baseline
baseline=/var/tmp/ihtd-upgrade-baseline/ihtd-0.2.5-1.fc44.x86_64.rpm
dnf install -y "$baseline"
[[ "$(rpm -q --queryformat '%{VERSION}' ihtd)" == 0.2.5 ]]
id ihtd-smoke >/dev/null 2>&1 || useradd --create-home ihtd-smoke
runtime_dir="$(mktemp -d /var/tmp/ihtd-smoke.XXXXXX)"
work="$(mktemp -d /var/tmp/ihtd-upgrade.XXXXXX)"
mkdir -p "$work/data" "$work/config" "$work/cache"
cp app/test/fixtures/upgrade-0.2.5/intact.sqlite "$work/Collection.ihtd"
cp app/test/fixtures/upgrade-0.2.5/pending.sqlite "$work/Unpublished working copy.ihtd"
sha256sum "$work/Collection.ihtd" "$work/Unpublished working copy.ihtd" > "$work/preservation.sha256"
chown -R ihtd-smoke:ihtd-smoke "$runtime_dir" "$work"

smoke() {
  local log="$1"
  shift
  set +e
  runuser -u ihtd-smoke -- env XDG_RUNTIME_DIR="$runtime_dir" XDG_DATA_HOME="$work/data" \
    XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache" GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
    dbus-run-session -- xvfb-run -a timeout 15s /usr/bin/ihtd "$@" > "$log" 2>&1
  local result=$?
  set -e
  cat "$log"
  if [[ "$result" != 124 ]]; then
    printf 'Release exited early (status %s).\n' "$result" >&2
    exit 1
  fi
}
smoke /workspace/fedora-baseline-smoke.log "$work/Collection.ihtd"
# Include actual baseline-created private document files in the preservation check.
python3 - "$work/data" "$work/preservation.sha256" <<'PY'
import hashlib
from pathlib import Path
import sys
with open(sys.argv[2], 'a') as manifest:
    files = list(Path(sys.argv[1]).rglob('*.ihtd'))
    assert files, 'Baseline app did not create its private working document'
    for path in files:
        manifest.write(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n')
PY

dnf upgrade -y "./dist/fedora/ihtd-$version-1.fc44.x86_64.rpm"
[[ "$(rpm -q --queryformat '%{VERSION}' ihtd)" == "$version" ]]
rpm -V ihtd
sha256sum -c "$work/preservation.sha256"
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
smoke /workspace/fedora-release-smoke.log
sha256sum -c "$work/preservation.sha256"
dnf remove -y ihtd
sha256sum -c "$work/preservation.sha256"
dnf install -y "./dist/fedora/ihtd-$version-1.fc44.x86_64.rpm"
smoke /workspace/fedora-reinstall-smoke.log "$work/Collection.ihtd"
sha256sum -c "$work/preservation.sha256"
printf '%s\n' 'Real v0.2.5 upgrade, ordinary-user launches, uninstall/reinstall and preserved external/private data verified.'
