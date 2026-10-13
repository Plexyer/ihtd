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
    def test_all_platforms_assemble_without_name_collisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packages = {
                'android': ['IHTD-0.2.1-android-arm64-test.apk'],
                'windows': ['IHTD-0.2.1-windows-x64.zip'],
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
            self.assertEqual(len(list((root / 'out').iterdir())), 8)
            self.assertEqual((root / 'out/INSTALL-android.md').read_text(), 'android')

    def test_tag_must_match(self):
        version = module('release-version')
        current = version.read_version()
        self.assertEqual(version.read_version(tag=f'v{current["version"]}'), current)
        with self.assertRaises(ValueError):
            version.read_version(tag='v999.0.0')

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
