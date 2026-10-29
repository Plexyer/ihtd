"""Protect the shared policy/UI boundary from accidental platform coupling."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ArchitectureBoundaryTest(unittest.TestCase):
    def test_shared_policy_and_ui_do_not_select_platforms_or_import_native_adapters(self):
        paths = list((ROOT / 'app/lib/ui').glob('*.dart'))
        paths += [ROOT / 'app/lib/services/document_save_coordinator.dart',
                  ROOT / 'app/lib/services/migration_safety.dart',
                  ROOT / 'app/lib/services/item_draft.dart',
                  ROOT / 'app/lib/services/app_controller.dart',
                  ROOT / 'app/lib/services/update_coordinator.dart',
                  ROOT / 'app/lib/services/update_catalog.dart']
        for path in paths:
            source = path.read_text()
            with self.subTest(file=path.name):
                self.assertNotRegex(source, r'Platform\.is(?:Android|Windows|Linux)')
                self.assertNotRegex(source, r"import\s+['\"][^'\"]*(?:android_documents|filesystem_documents)\.dart")

    def test_update_pins_match_permanent_signing_identity(self):
        pin = (ROOT / 'packaging/android/release-certificate.sha256').read_text().strip()
        for name in ['app/lib/services/update_contract.dart',
                     'app/android/app/src/main/kotlin/dev/ihtd/app/UpdateBridge.kt']:
            self.assertIn(pin, (ROOT / name).read_text())



if __name__ == '__main__':
    unittest.main()
