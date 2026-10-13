import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('android_signing',
    Path(__file__).resolve().parents[1] / 'android-signing.py')
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def test_unconfigured_or_malformed_certificate_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            certificate = Path(temporary) / 'certificate'
            with self.assertRaises(ValueError):
                signing.fingerprint(certificate)
            certificate.write_text('debug-key')
            with self.assertRaises(ValueError):
                signing.fingerprint(certificate)

    def test_wrong_or_multiple_signers_are_rejected(self):
        for output in ('Signer #1 certificate SHA-256 digest: ' + 'a' * 64,
                       'Signer #1 certificate SHA-256 digest: ' + 'b' * 64 + '\n' +
                       'Signer #2 certificate SHA-256 digest: ' + 'b' * 64):
            with self.subTest(output=output), patch.object(signing, 'run', return_value=output):
                with self.assertRaises(ValueError):
                    signing.verify(Path('example.apk'), 'b' * 64, 'apksigner')

    def test_existing_key_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            key = Path(temporary) / 'key.p12'
            key.write_bytes(b'owner-key')
            with self.assertRaises(ValueError):
                signing.generate(key, 'alias', Path(temporary) / 'cert', password='x' * 24)
            self.assertEqual(key.read_bytes(), b'owner-key')
