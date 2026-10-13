"""Validate the shared version before building; usable on every CI runner."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_version(root=ROOT, tag=None):
    lines = (root / 'app/pubspec.yaml').read_text().splitlines()
    values = [line.removeprefix('version: ').strip() for line in lines
              if line.startswith('version: ')]
    if len(values) != 1 or not re.fullmatch(
            r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+[1-9]\d*', values[0]):
        raise ValueError('Expected one version: X.Y.Z+BUILD in app/pubspec.yaml')
    version, build = values[0].split('+')
    if int(build) > 2100000000:
        raise ValueError('Android build code exceeds its supported range')
    if tag is not None and tag != f'v{version}':
        raise ValueError(f'Tag {tag!r} must equal v{version}')
    spec = (root / 'packaging/fedora/ihtd.spec').read_text()
    if re.search(r'^Version:\s*(\S+)$', spec, re.M).group(1) != version:
        raise ValueError('Fedora spec version differs from app/pubspec.yaml')
    return {'version': version, 'build': build}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag')
    parser.add_argument('--github-output')
    args = parser.parse_args()
    result = read_version(tag=args.tag)
    if args.github_output:
        with open(args.github_output, 'a', encoding='utf-8') as output:
            for key, value in result.items():
                output.write(f'{key}={value}\n')
    print(json.dumps(result))
