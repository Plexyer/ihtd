"""Verify each platform manifest and stage unique assets for one draft release."""
import hashlib
import os
from pathlib import Path
import shutil
import sys


def assemble(source, destination, version, production=False, certificate=None):
    expected = {
        'android': [f'IHTD-{version}-android-arm64-test.apk'],
        'windows': [f'IHTD-{version}-windows-x64.zip'],
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
    destination.mkdir(parents=True, exist_ok=False)
    lines = []
    for path, name, digest in assets:
        shutil.copyfile(path, destination / name)
        lines.append(f'{digest}  {name}')
    (destination / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    assemble(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3],
             production=os.environ.get('PRODUCTION_ANDROID') == 'true')
