"""Verify each platform manifest and stage unique assets for one draft release."""
import hashlib
import json
import re
import subprocess
import importlib.util
import os
from pathlib import Path
import shutil
import sys


def assemble(source, destination, version, production=False, certificate=None,
             build=None, commit=None):
    expected = {
        'android': [f'IHTD-{version}-android-arm64-test.apk'],
        'windows': [f'IHTD-{version}-windows-x64.zip',
                    f'IHTD-{version}-windows-x64-setup.exe'],
        'fedora': [f'ihtd-{version}-1.fc44.x86_64.rpm',
                   f'IHTD-{version}-fedora44-x86_64.tar.gz'],
    }
    if production:
        if certificate is None:
            certificate = (Path(__file__).resolve().parents[1] /
                           'packaging/android/release-certificate.sha256').read_text().strip().lower()
        if len(certificate) != 64 or any(c not in '0123456789abcdef' for c in certificate):
            raise ValueError('Permanent signing certificate is not configured')
        expected['android'] = [f'IHTD-{version}-android-arm64.apk', 'SIGNING-CERTIFICATE.sha256']
        actual = (source / 'android-package/SIGNING-CERTIFICATE.sha256').read_text().strip().lower()
        if actual != certificate:
            raise ValueError('Android certificate does not match the pinned release identity')
    assets = []
    for platform, names in expected.items():
        directory = source / f'{platform}-package'
        manifest = {}
        for line in (directory / 'SHA256SUMS').read_text(encoding='utf-8-sig').splitlines():
            digest, name = line.split(maxsplit=1)
            name = name.removeprefix('*')
            if name in manifest:
                raise ValueError('Duplicate checksum entry')
            manifest[name] = digest.lower()
        if set(manifest) != set(names):
            raise ValueError(f'{platform}: unexpected or missing packages')
        for name in names:
            path = directory / name
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != manifest[name]:
                raise ValueError(f'Checksum mismatch: {name}')
            assets.append((path, name, digest))
        guide = directory / 'INSTALL.md'
        if not guide.is_file():
            raise ValueError(f'{platform}: installation guide missing')
        assets.append((guide, f'INSTALL-{platform}.md', hashlib.sha256(guide.read_bytes()).hexdigest()))
    update = None
    if production:
        if build is None:
            spec = importlib.util.spec_from_file_location('release_version',
                    Path(__file__).with_name('release-version.py'))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            current = module.read_version(tag=f'v{version}')
            build = int(current['build'])
        if commit is None:
            commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
        if not isinstance(build, int) or not 0 < build <= 2100000000 or not re.fullmatch(r'[a-f0-9]{40}', commit):
            raise ValueError('Invalid update release identity')
        packages = []
        for platform, arch, name in [
            ('android', 'arm64', f'IHTD-{version}-android-arm64.apk'),
            ('windows', 'x64', f'IHTD-{version}-windows-x64-setup.exe'),
            ('fedora', 'x64', f'ihtd-{version}-1.fc44.x86_64.rpm'),
        ]:
            path, _, digest = next(a for a in assets if a[1] == name)
            if not 0 < path.stat().st_size <= 536870912:
                raise ValueError('Update package exceeds supported size')
            entry = dict(platform=platform, arch=arch, name=name,
                         size=path.stat().st_size, sha256=digest)
            if platform == 'android':
                entry.update(minApi=35, packageId='dev.ihtd.app', certificate=certificate)
            elif platform == 'fedora':
                entry.update(distribution='fedora44')
            packages.append(entry)
        update = dict(schema=1, version=version, build=build, tag=f'v{version}',
                      commit=commit, packages=packages)
    destination.mkdir(parents=True, exist_ok=False)
    lines = []
    for path, name, digest in assets:
        shutil.copyfile(path, destination / name)
        lines.append(f'{digest}  {name}')
    if update is not None:
        metadata = (json.dumps(update, indent=2, sort_keys=True) + '\n').encode()
        (destination / 'update.json').write_bytes(metadata)
        lines.append(f'{hashlib.sha256(metadata).hexdigest()}  update.json')
    (destination / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    assemble(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3],
             production=os.environ.get('PRODUCTION_ANDROID') == 'true')
