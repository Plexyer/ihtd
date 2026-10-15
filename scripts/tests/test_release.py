import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f'{name}.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class ReleaseTests(unittest.TestCase):
    def test_production_rejects_wrong_certificate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / 'android-package'
            directory.mkdir()
            (directory / 'SIGNING-CERTIFICATE.sha256').write_text('a' * 64)
            with self.assertRaises(ValueError):
                module('assemble-release').assemble(root, root / 'out', '0.2.1',
                                                   production=True, certificate='b' * 64)
            self.assertFalse((root / 'out').exists())

    def test_all_platforms_assemble_without_name_collisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packages = {
                'android': ['IHTD-0.2.1-android-arm64-test.apk'],
                'windows': ['IHTD-0.2.1-windows-x64.zip',
                            'IHTD-0.2.1-windows-x64-setup.exe'],
                'fedora': ['ihtd-0.2.1-1.fc44.x86_64.rpm',
                           'IHTD-0.2.1-fedora44-x86_64.tar.gz'],
            }
            for platform, names in packages.items():
                directory = root / f'{platform}-package'
                directory.mkdir()
                lines = []
                for name in names:
                    payload = name.encode()
                    (directory / name).write_bytes(payload)
                    lines.append(f'{hashlib.sha256(payload).hexdigest()}  {name}')
                (directory / 'SHA256SUMS').write_text('\n'.join(lines))
                (directory / 'INSTALL.md').write_text(platform)
            module('assemble-release').assemble(root, root / 'out', '0.2.1')
            self.assertEqual(len(list((root / 'out').iterdir())), 9)
            self.assertTrue((root / 'out/IHTD-0.2.1-windows-x64-setup.exe').is_file())
            self.assertEqual((root / 'out/INSTALL-android.md').read_text(), 'android')

    def test_production_metadata_contains_only_complete_verified_packages(self):
        import json
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            version = '0.2.3'
            certificate = 'a' * 64
            names = {
                'android': [f'IHTD-{version}-android-arm64.apk', 'SIGNING-CERTIFICATE.sha256'],
                'windows': [f'IHTD-{version}-windows-x64.zip', f'IHTD-{version}-windows-x64-setup.exe'],
                'fedora': [f'ihtd-{version}-1.fc44.x86_64.rpm', f'IHTD-{version}-fedora44-x86_64.tar.gz'],
            }
            for platform, files in names.items():
                directory = root / f'{platform}-package'
                directory.mkdir()
                checksums = []
                for name in files:
                    payload = certificate.encode() if name == 'SIGNING-CERTIFICATE.sha256' else name.encode()
                    (directory / name).write_bytes(payload)
                    checksums.append(f'{hashlib.sha256(payload).hexdigest()}  {name}')
                (directory / 'SHA256SUMS').write_text('\n'.join(checksums))
                (directory / 'INSTALL.md').write_text('Instructions')
            module('assemble-release').assemble(root, root / 'out', version, production=True,
                certificate=certificate, build=12, commit='b' * 40)
            metadata = json.loads((root / 'out/update.json').read_text())
            self.assertEqual(metadata['build'], 12)
            self.assertEqual(metadata['tag'], 'v0.2.3')
            self.assertEqual(len(metadata['packages']), 3)
            android = metadata['packages'][0]
            self.assertEqual(android['certificate'], certificate)
            self.assertEqual(android['packageId'], 'dev.ihtd.app')
            self.assertEqual(android['minApi'], 35)
            self.assertIn('update.json', (root / 'out/SHA256SUMS').read_text())

    def test_tag_must_match(self):
        version = module('release-version')
        current = version.read_version()
        self.assertEqual(version.read_version(tag=f'v{current["version"]}'), current)
        with self.assertRaises(ValueError):
            version.read_version(tag='v999.0.0')

    def test_portable_zip_without_installer_cannot_be_released(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for platform, name in [
                ('android', 'IHTD-0.2.1-android-arm64-test.apk'),
                ('windows', 'IHTD-0.2.1-windows-x64.zip'),
            ]:
                directory = root / f'{platform}-package'
                directory.mkdir()
                (directory / name).write_bytes(b'package')
                digest = hashlib.sha256(b'package').hexdigest()
                (directory / 'SHA256SUMS').write_text(f'{digest}  {name}\n')
                (directory / 'INSTALL.md').write_text(platform)
            with self.assertRaisesRegex(ValueError, 'windows: unexpected or missing packages'):
                module('assemble-release').assemble(root, root / 'out', '0.2.1')
            self.assertFalse((root / 'out').exists())

    def test_missing_platform_prevents_assembly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(FileNotFoundError):
                module('assemble-release').assemble(root, root / 'out', '0.2.1')
            self.assertFalse((root / 'out').exists())

    def test_tampering_prevents_assembly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            android = root / 'android-package'
            android.mkdir()
            name = 'IHTD-0.2.1-android-arm64-test.apk'
            (android / name).write_bytes(b'tampered')
            (android / 'SHA256SUMS').write_text(f'{hashlib.sha256(b"original").hexdigest()}  {name}\n')
            with self.assertRaises(ValueError):
                module('assemble-release').assemble(root, root / 'out', '0.2.1')
            self.assertFalse((root / 'out').exists())
