#!/usr/bin/env python3
"""Audit normal/delay PE imports using the target Windows system DLL set."""
import argparse
import json
import os
import struct
from pathlib import Path


def imports(path):
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError(f'{path}: not a PE image')
    machine, count = struct.unpack_from('<HH', data, pe + 4)
    if machine != 0x8664:
        raise ValueError(f'{path}: expected x64, got {machine:#x}')
    opt_size = struct.unpack_from('<H', data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', data, opt)[0]
    if magic != 0x20b:
        raise ValueError(f'{path}: expected PE32+')
    image_base = struct.unpack_from('<Q', data, opt + 24)[0]
    directories = opt + 112
    sections = []
    for n in range(count):
        size, address, raw_size, raw = struct.unpack_from('<IIII', data, opt + opt_size + n * 40 + 8)
        sections.append((address, max(size, raw_size), raw))

    def offset(rva):
        for address, size, raw in sections:
            if address <= rva < address + size:
                return raw + rva - address
        if rva < struct.unpack_from('<I', data, opt + 60)[0]:
            return rva
        raise ValueError(f'{path}: unmapped RVA {rva:#x}')

    names = set()
    for index, width, fields in ((1, 20, 5), (13, 32, 8)):
        rva, length = struct.unpack_from('<II', data, directories + index * 8)
        if not rva:
            continue
        start = offset(rva)
        for position in range(start, min(start + length, len(data)), width):
            values = struct.unpack_from('<' + 'I' * fields, data, position)
            if not any(values):
                break
            name = values[3] if index == 1 else values[1]
            if index == 13 and not values[0] & 1:
                name -= image_base
            name_offset = offset(name)
            names.add(data[name_offset:data.index(b'\0', name_offset)].decode('ascii').lower())
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('package', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    executables = list(args.package.rglob('vlc.exe'))
    if len(executables) != 1:
        raise ValueError('Expected one packaged vlc.exe')
    root = executables[0].parent
    system = Path(os.environ['SystemRoot']) / 'System32'
    system_dlls = {p.name.lower() for p in system.glob('*.dll')}
    root_dlls = {p.name.lower() for p in root.glob('*.dll')}
    missing = []
    images = [p for p in root.rglob('*') if p.suffix.lower() in ('.exe', '.dll')]
    for path in images:
        local = {p.name.lower() for p in path.parent.glob('*.dll')}
        for dependency in imports(path):
            if dependency.startswith(('api-ms-', 'ext-ms-')):
                continue
            if dependency not in system_dlls | root_dlls | local:
                missing.append({'image': str(path.relative_to(root)), 'missing_dll': dependency})
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({'images_checked': len(images), 'missing': missing}, indent=2))
    print(json.dumps({'images_checked': len(images), 'missing': missing}, indent=2))
    return bool(missing)


if __name__ == '__main__':
    raise SystemExit(main())
