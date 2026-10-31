#!/usr/bin/env python3
"""Download a pinned public baseline package for disposable upgrade validation.
This only downloads/verifies; it never runs an installer or changes an installed app.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT/'packaging/upgrade-baseline.json'
HOSTS = {'github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com'}


class Redirects(HTTPRedirectHandler):
    def __init__(self): self.count = 0
    def redirect_request(self, request, fp, code, message, headers, newurl):
        self.count += 1
        target = urlparse(newurl)
        if self.count > 5 or target.scheme != 'https' or target.hostname not in HOSTS or target.username or target.password:
            raise ValueError('Unexpected baseline download redirect')
        return super().redirect_request(request,fp,code,message,headers,newurl)


def verified(path, asset):
    return path.stat().st_size == asset['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == asset['sha256']


def download(platform, output, opener=None):
    catalog = json.loads(CATALOG.read_text())
    asset = catalog['assets'][platform]
    name = asset['name']
    assert Path(name).name == name and '/' not in name and '\\' not in name
    output.mkdir(parents=True,exist_ok=True)
    target = output/name
    if target.exists():
        if not verified(target,asset): raise ValueError('Existing baseline package failed verification; refusing overwrite')
        return target
    opener = opener or build_opener(Redirects())
    url = f"https://github.com/Plexyer/ihtd/releases/download/{catalog['tag']}/{name}"
    handle, temporary = tempfile.mkstemp(prefix='ihtd-baseline-',suffix='.part',dir=output)
    temporary = Path(temporary)
    try:
        received = 0
        with os.fdopen(handle,'wb') as destination, opener.open(Request(url,headers={'User-Agent':'IHTD-upgrade-validation'}),timeout=30) as response:
            while chunk := response.read(1024*1024):
                received += len(chunk)
                if received > asset['size']: raise ValueError('Baseline package exceeds its pinned size')
                destination.write(chunk)
            destination.flush(); os.fsync(destination.fileno())
        if not verified(temporary,asset): raise ValueError('Baseline size/checksum verification failed')
        # Exclusive publication; never replace an unrelated existing file.
        os.link(temporary,target)
        return target
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform',choices=['windows','fedora','android'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    print(json.dumps({'path':str(download(args.platform,args.output).resolve())}))
