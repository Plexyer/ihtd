#!/usr/bin/env python3
"""Package synthetic upgrade data and manual test instructions; no executables."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def package(output, version, build, commit):
    fixture = ROOT/'app/test/fixtures/upgrade-0.2.5'
    manifest = json.loads((fixture/'manifest.json').read_text())
    data = {
        '01-intact-default.ihtd':(fixture/'intact.sqlite').read_bytes(),
        '02-customized-default.ihtd':(fixture/'customized.sqlite').read_bytes(),
        '03-deleted-default.ihtd':(fixture/'deleted-default.sqlite').read_bytes(),
        '04-unpublished-working-snapshot.ihtd':(fixture/'pending.sqlite').read_bytes(),
        'GUIDE.md':(ROOT/'docs/upgrade-acceptance.md').read_bytes(),
        'RESULTS.md':(ROOT/'docs/upgrade-acceptance-results.md').read_bytes(),
        'LICENSE':(ROOT/'LICENSE').read_bytes(),
        'PROVENANCE.json':json.dumps({'candidate':{'version':version,'build':build,'commit':commit},
            'fixtures':manifest},indent=2).encode(),
    }
    data['README.md'] = f'''# IHTD {version} (build {build}) upgrade tests

These are synthetic files produced with the actual v0.2.5 model/SQLite writer.
They contain no personal collection data and no installation program.

1. Extract this ZIP to a test folder you can find in Files / My Files / Explorer.
2. Use the permanently signed candidate APK or the reviewed desktop installer
   described in GUIDE.md. Keep your existing app and its data installed.
3. Open copies of the numbered .ihtd files in IHTD and follow GUIDE.md.
4. Record the real device and results in RESULTS.md; leave untested rows pending.

The snapshots deliberately share a collection UUID to exercise file isolation.
They are separate files: edits to one must never overwrite another. File 04
contains example unpublished working contents; opening it does not reconnect
another file's private recovery. GUIDE.md covers the real disconnect/restart test.

Candidate source: https://github.com/Plexyer/ihtd/tree/{commit}
Baseline source: https://github.com/Plexyer/ihtd/tree/{manifest['baselineCommit']}
'''.encode()
    output.mkdir(parents=True,exist_ok=True)
    path = output/f'IHTD-{version}-upgrade-tests.zip'
    with zipfile.ZipFile(path,'x',compression=zipfile.ZIP_DEFLATED) as archive:
        for name, payload in sorted(data.items()):
            info = zipfile.ZipInfo(name,date_time=(2026,10,31,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info,payload)
    return path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    spec=importlib.util.spec_from_file_location('version',ROOT/'scripts/release-version.py')
    metadata=importlib.util.module_from_spec(spec);spec.loader.exec_module(metadata)
    version=metadata.read_version()
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    path=package(args.output,version['version'],int(version['build']),commit)
    print(json.dumps({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}))
