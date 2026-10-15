import importlib.util
import io
from pathlib import Path
import struct
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'verify_android_apk', Path(__file__).resolve().parents[1] / 'verify-android-apk.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ApkAlignmentTests(unittest.TestCase):
    def archive(self, alignment, *, file_offset=0):
        elf = bytearray(120)
        elf[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<Q', elf, 32, 64)
        struct.pack_into('<HH', elf, 54, 56, 1)
        struct.pack_into('<IIQQQQQQ', elf, 64, 1, 5, file_offset, 0, 0, 0, 0, alignment)
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('lib/arm64-v8a/libihtd_bridge.so', elf)
        output.seek(0)
        return output

    def test_16kb_and_64kb_load_segments_are_accepted(self):
        for alignment in (16384, 65536):
            self.assertEqual(module.verify(self.archive(alignment))[0][1], [alignment])

    def test_4kb_library_is_rejected_even_inside_a_valid_zip(self):
        with self.assertRaisesRegex(ValueError, 'LOAD alignment 4096'):
            module.verify(self.archive(4096))

    def test_misaligned_file_and_address_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'incongruent'):
            module.verify(self.archive(16384, file_offset=1))


if __name__ == '__main__':
    unittest.main()
