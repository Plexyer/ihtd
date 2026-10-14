"""Protect the shared policy/UI boundary from accidental platform coupling."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ArchitectureBoundaryTest(unittest.TestCase):
    def test_shared_policy_and_ui_do_not_select_platforms_or_import_native_adapters(self):
        paths = list((ROOT / 'app/lib/ui').glob('*.dart'))
        paths += [ROOT / 'app/lib/services/document_save_coordinator.dart',
                  ROOT / 'app/lib/services/app_controller.dart']
        for path in paths:
            source = path.read_text()
            with self.subTest(file=path.name):
                self.assertNotRegex(source, r'Platform\.is(?:Android|Windows|Linux)')
                self.assertNotRegex(source, r"import\s+['\"][^'\"]*(?:android_documents|filesystem_documents)\.dart")


if __name__ == '__main__':
    unittest.main()
