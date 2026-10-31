import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.request import Request
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'scripts'/f'{name}.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class UpgradeBaselineTest(unittest.TestCase):
    def test_released_encoder_fixture_provenance_and_closed_snapshots(self):
        module('generate-upgrade-fixtures').check()

    def test_verified_download_and_cache_without_execution(self):
        downloader = module('download-upgrade-baseline')
        payload = b'synthetic baseline package'
        asset = {'name':'baseline.exe', 'size':len(payload),
                 'sha256':hashlib.sha256(payload).hexdigest()}

        class Opener:
            calls = 0
            def open(self, request, timeout):
                self.calls += 1
                assert request.full_url == 'https://github.com/Plexyer/ihtd/releases/download/v0.2.5/baseline.exe'
                return io.BytesIO(payload)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog = root/'catalog.json'
            catalog.write_text(json.dumps({'tag':'v0.2.5', 'assets':{'windows':asset}}))
            with patch.object(downloader, 'CATALOG', catalog):
                opener = Opener()
                path = downloader.download('windows', root/'downloads', opener)
                self.assertEqual(path.read_bytes(), payload)
                self.assertEqual(downloader.download('windows', root/'downloads', opener), path)
                self.assertEqual(opener.calls, 1)
                path.write_bytes(b'existing unrelated file')
                with self.assertRaisesRegex(ValueError, 'refusing overwrite'):
                    downloader.download('windows', root/'downloads', opener)
                self.assertEqual(path.read_bytes(), b'existing unrelated file')

    def test_corruption_truncation_and_size_overflow_never_publish(self):
        downloader = module('download-upgrade-baseline')
        for payload in [b'evil', b'go', b'good plus unbounded content']:
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                catalog = root/'catalog.json'
                catalog.write_text(json.dumps({'tag':'v0.2.5', 'assets':{'windows':{
                    'name':'baseline.exe', 'size':4, 'sha256':hashlib.sha256(b'good').hexdigest()}}}))
                class Opener:
                    def open(self, request, timeout): return io.BytesIO(payload)
                with patch.object(downloader, 'CATALOG', catalog):
                    with self.assertRaises(ValueError):
                        downloader.download('windows', root/'downloads', Opener())
                self.assertEqual(list((root/'downloads').iterdir()), [])

    def test_download_redirect_policy_rejects_external_or_insecure_destinations(self):
        downloader = module('download-upgrade-baseline')
        request = Request('https://github.com/Plexyer/ihtd/releases/download/v0.2.5/file')
        for url in ['http://github.com/file', 'https://example.com/file',
                    'https://github.com.attacker.invalid/file', 'https://user@github.com/file']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                downloader.Redirects().redirect_request(request, None, 302, 'Found', {}, url)
        handler = downloader.Redirects()
        for _ in range(5):
            self.assertIsNotNone(handler.redirect_request(request, None, 302, 'Found', {},
                'https://release-assets.githubusercontent.com/asset'))
        with self.assertRaises(ValueError):
            handler.redirect_request(request, None, 302, 'Found', {}, 'https://github.com/file')

    def test_test_kit_preserves_released_bytes_and_contains_only_document_data(self):
        packager = module('package-upgrade-fixtures')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = packager.package(root/'one', '0.3.0', 15, 'a'*40)
            second = packager.package(root/'two', '0.3.0', 15, 'a'*40)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(set(archive.namelist()), {
                    '01-intact-default.ihtd', '02-customized-default.ihtd',
                    '03-deleted-default.ihtd', '04-unpublished-working-snapshot.ihtd',
                    'GUIDE.md', 'RESULTS.md', 'LICENSE', 'PROVENANCE.json', 'README.md'})
                for filename, fixture in [('01-intact-default.ihtd','intact'),
                     ('02-customized-default.ihtd','customized'),
                     ('03-deleted-default.ihtd','deleted-default'),
                     ('04-unpublished-working-snapshot.ihtd','pending')]:
                    self.assertEqual(archive.read(filename),
                        (ROOT/f'app/test/fixtures/upgrade-0.2.5/{fixture}.sqlite').read_bytes())
                provenance = json.loads(archive.read('PROVENANCE.json'))
                self.assertEqual(provenance['candidate'], {'version':'0.3.0','build':15,'commit':'a'*40})
                catalog = json.loads((ROOT/'packaging/upgrade-baseline.json').read_text())
                self.assertEqual(provenance['fixtures']['baselineCommit'], catalog['commit'])
            with self.assertRaises(FileExistsError):
                packager.package(root/'one', '0.3.0', 15, 'a'*40)
