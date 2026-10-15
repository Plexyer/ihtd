#!/usr/bin/env python3
"""Check native ELF load segments, separately from APK ZIP/signature checks."""
import argparse
import struct
import sys
import zipfile


def verify(apk):
    checked = []
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            if not name.startswith('lib/') or not name.endswith('.so'):
                continue
            data = archive.read(name)
            if len(data) < 64 or data[:6] != b'\x7fELF\x02\x01':
                raise ValueError(f'{name}: expected little-endian ELF64')
            offset = struct.unpack_from('<Q', data, 32)[0]
            size, count = struct.unpack_from('<HH', data, 54)
            if size < 56 or count == 0 or offset + size * count > len(data):
                raise ValueError(f'{name}: invalid program headers')
            aligns = []
            for index in range(count):
                entry = struct.unpack_from('<IIQQQQQQ', data, offset + index * size)
                if entry[0] != 1:  # PT_LOAD
                    continue
                align = entry[7]
                if align < 16384 or align & (align - 1):
                    raise ValueError(f'{name}: LOAD alignment {align}, requires >= 16384')
                if entry[2] % align != entry[3] % align:
                    raise ValueError(f'{name}: incongruent LOAD file/address alignment')
                aligns.append(align)
            if not aligns:
                raise ValueError(f'{name}: no LOAD segments')
            checked.append((name, sorted(set(aligns))))
    if not checked:
        raise ValueError('APK contains no native libraries')
    return checked


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    args = parser.parse_args()
    try:
        for name, aligns in verify(args.apk):
            print(f'{name}: LOAD alignment {aligns}')
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f'APK native alignment validation failed: {error}', file=sys.stderr)
        sys.exit(1)
