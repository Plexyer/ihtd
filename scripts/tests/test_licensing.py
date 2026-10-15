"""Keep project licensing/source access consistent across distribution metadata."""
from pathlib import Path
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LicensingTests(unittest.TestCase):
    def test_complete_license_is_identical_in_flutter_package(self):
        text = (ROOT / 'LICENSE').read_bytes()
        self.assertEqual(text, (ROOT / 'app/LICENSE').read_bytes())
        self.assertIn(b'GNU AFFERO GENERAL PUBLIC LICENSE', text)
        self.assertIn(b'13. Remote Network Interaction', text)
        self.assertIn(b'END OF TERMS AND CONDITIONS', text)

    def test_our_crate_and_rpm_license_metadata_match(self):
        workspace = tomllib.loads((ROOT / 'Cargo.toml').read_text())
        self.assertEqual(workspace['workspace']['package']['license'], 'AGPL-3.0-only')
        for name in ['ihtd_app', 'ihtd_core']:
            crate = tomllib.loads((ROOT / f'crates/{name}/Cargo.toml').read_text())
            self.assertTrue(crate['package']['license']['workspace'])
        bridge = tomllib.loads((ROOT / 'app/rust/Cargo.toml').read_text())
        self.assertEqual(bridge['package']['license'], 'AGPL-3.0-only')
        self.assertIn('License: AGPL-3.0-only', (ROOT / 'packaging/fedora/ihtd.spec').read_text())
