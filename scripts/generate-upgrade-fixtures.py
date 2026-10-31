#!/usr/bin/env python3
"""Produce synthetic acceptance files using the actual released v0.2.5 crates.
Normal CI uses --check; regeneration needs the local historical Git objects and
Rust 1.93.1 with the baseline's locked dependencies already cached.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'ec7144a6a03dc666e3fad885e1fe1562cf144569'
TAG = 'v0.2.5'
OUTPUT = ROOT/'app/test/fixtures/upgrade-0.2.5'
PRODUCER = ROOT/'scripts/upgrade-fixture-producer.rs'
NAMES = ['intact','customized','deleted-default','pending']


def digest(path):
    data = path.read_bytes()
    if path.suffix in {'.json','.py','.rs'}:
        data = data.replace(b'\r\n',b'\n')
    return hashlib.sha256(data).hexdigest()


def check():
    manifest = json.loads((OUTPUT/'manifest.json').read_text())
    assert manifest['baselineTag'] == TAG and manifest['baselineCommit'] == BASELINE
    assert manifest['producer'] == digest(PRODUCER), 'Producer changed; regenerate fixtures.'
    expected = sorted(['roles.json']+[f'{n}.{ext}' for n in NAMES for ext in ['sqlite','json']])
    assert sorted(manifest['files']) == expected
    for name, sha in manifest['files'].items():
        assert digest(OUTPUT/name) == sha, f'Upgrade fixture drift: {name}'
    for name in NAMES:
        path = (OUTPUT/f'{name}.sqlite').resolve()
        with sqlite3.connect(path.as_uri()+'?mode=ro',uri=True) as db:
            assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            assert db.execute('PRAGMA user_version').fetchone()[0] == 2
            assert dict(db.execute('SELECT key,value FROM metadata'))['document_id'] == 'synthetic-released-0.2.5-collection'
    print('Released-format fixtures verified: v0.2.5, four closed SQLite files.')


def generate(toolchain):
    import tomllib
    commit = subprocess.check_output(['git','rev-parse',f'{TAG}^{{commit}}'],cwd=ROOT,text=True).strip()
    assert commit == BASELINE, 'Historical tag changed; investigate rather than changing provenance.'
    with tempfile.TemporaryDirectory(prefix='ihtd-released-producer-') as temp:
        temp = Path(temp); checkout = temp/'baseline'; checkout.mkdir()
        archive = temp/'baseline.tar'
        with archive.open('wb') as target:
            subprocess.run(['git','archive',BASELINE,'Cargo.toml','Cargo.lock','crates'],cwd=ROOT,stdout=target,check=True)
        with tarfile.open(archive) as source:
            source.extractall(checkout,filter='data')
        lock = tomllib.loads((checkout/'Cargo.lock').read_text())
        cargo = checkout/'Cargo.toml'
        cargo.write_text(cargo.read_text().replace('members = [','members = ["upgrade-fixture-producer", '),newline='\n')
        package = checkout/'upgrade-fixture-producer'; (package/'src').mkdir(parents=True)
        (package/'Cargo.toml').write_text('''[package]
name = "upgrade-fixture-producer"
version = "0.0.0"
edition = "2021"
license = "AGPL-3.0-only"
[dependencies]
ihtd_core = { path = "../crates/ihtd_core" }
ihtd_app = { path = "../crates/ihtd_app" }
serde_json = "1"
''',newline='\n')
        (package/'src/main.rs').write_bytes(PRODUCER.read_bytes())
        generated = temp/'generated'
        subprocess.run(['cargo',f'+{toolchain}','run','--offline','--manifest-path',str(cargo),
            '--package','upgrade-fixture-producer','--',str(generated)],cwd=ROOT,check=True)
        after = tomllib.loads((checkout/'Cargo.lock').read_text())
        assert [p for p in after['package'] if p['name']!='upgrade-fixture-producer'] == lock['package'], 'Baseline dependency lock changed.'
        OUTPUT.mkdir(parents=True,exist_ok=True)
        for name in ['roles.json']+[f'{n}.{ext}' for n in NAMES for ext in ['sqlite','json']]:
            (OUTPUT/name).write_bytes((generated/name).read_bytes())
        files = {p.name:digest(p) for p in sorted(OUTPUT.iterdir()) if p.name!='manifest.json'}
        (OUTPUT/'manifest.json').write_text(json.dumps({
            'formatVersion':1,'baselineTag':TAG,'baselineCommit':BASELINE,
            'producer':digest(PRODUCER),'toolchain':toolchain,'files':files,
        },indent=2)+'\n',newline='\n')
    check()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--toolchain',default='1.93.1')
    args = parser.parse_args()
    if args.check: check()
    else: generate(args.toolchain)
