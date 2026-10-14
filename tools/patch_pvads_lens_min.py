#!/usr/bin/env python3
"""Lower Project Viewpoint ADS's hard-coded minimum scope-overlay radius.

This is a local compatibility patch for the upstream ProjectViewpointADS.jar.
It changes only the lower clamp in pvads.ADS.projectOverlay from 0.1 screen
heights to 0.001, allowing the existing Lens size calibration to work below
the upstream visual floor. The original JAR is backed up next to the input.
"""

from __future__ import annotations

import argparse
import os
import shutil
import struct
import tempfile
import zipfile


def u2(data: bytes | bytearray, pos: int) -> int:
    return struct.unpack_from(">H", data, pos)[0]


def u4(data: bytes | bytearray, pos: int) -> int:
    return struct.unpack_from(">I", data, pos)[0]


def locate_patch(data: bytearray) -> tuple[int, str]:
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError("not a Java class file")

    cp_count = u2(data, 8)
    cp: list[tuple[int, object] | None] = [None] * cp_count
    utf8: dict[int, str] = {}
    pos = 10
    i = 1
    while i < cp_count:
        tag = data[pos]
        pos += 1
        if tag == 1:
            size = u2(data, pos)
            pos += 2
            value = bytes(data[pos:pos + size]).decode("utf-8", errors="replace")
            cp[i] = (tag, value)
            utf8[i] = value
            pos += size
        elif tag in (3, 4):
            raw = bytes(data[pos:pos + 4])
            value = struct.unpack(">f" if tag == 4 else ">i", raw)[0]
            cp[i] = (tag, value)
            pos += 4
        elif tag in (5, 6):
            cp[i] = (tag, None)
            pos += 8
            i += 1
        elif tag in (7, 8, 16, 19, 20):
            cp[i] = (tag, u2(data, pos))
            pos += 2
        elif tag in (9, 10, 11, 12, 17, 18):
            cp[i] = (tag, (u2(data, pos), u2(data, pos + 2)))
            pos += 4
        elif tag == 15:
            cp[i] = (tag, (data[pos], u2(data, pos + 1)))
            pos += 3
        else:
            raise ValueError(f"unsupported constant-pool tag {tag}")
        i += 1

    min_index = next((n for n, entry in enumerate(cp)
                      if entry and entry[0] == 4 and abs(float(entry[1]) - 0.001) < 1e-8), None)
    floor_index = next((n for n, entry in enumerate(cp)
                        if entry and entry[0] == 4 and abs(float(entry[1]) - 0.1) < 1e-6), None)
    if min_index is None or floor_index is None:
        raise ValueError("expected 0.001 and 0.1 float constants were not found")

    pos += 6  # access_flags, this_class, super_class
    interfaces = u2(data, pos)
    pos += 2 + interfaces * 2

    def skip_members(pos: int, count: int) -> int:
        for _ in range(count):
            pos += 6
            attrs = u2(data, pos)
            pos += 2
            for _ in range(attrs):
                length = u4(data, pos + 2)
                pos += 6 + length
        return pos

    fields = u2(data, pos)
    pos = skip_members(pos + 2, fields)
    methods = u2(data, pos)
    pos += 2
    target_pattern = bytes((0x13, floor_index >> 8, floor_index & 0xFF,
                            0x15, 0x05, 0x86, 0x6A))
    replacement = bytes((0x13, min_index >> 8, min_index & 0xFF))

    for _ in range(methods):
        name_index = u2(data, pos + 2)
        attrs = u2(data, pos + 6)
        pos += 8
        method_name = utf8.get(name_index, "")
        for _ in range(attrs):
            attr_name = utf8.get(u2(data, pos), "")
            length = u4(data, pos + 2)
            attr_start = pos + 6
            if method_name == "projectOverlay" and attr_name == "Code":
                code_length = u4(data, attr_start + 4)
                code_start = attr_start + 8
                code = bytes(data[code_start:code_start + code_length])
                hits = [j for j in range(len(code) - len(target_pattern) + 1)
                        if code[j:j + len(target_pattern)] == target_pattern]
                if len(hits) != 1:
                    raise ValueError(f"expected one lens-radius clamp in projectOverlay; found {len(hits)}")
                offset = code_start + hits[0]
                data[offset:offset + 3] = replacement
                return offset, f"projectOverlay: 0.1 -> 0.001 (constant #{floor_index} -> #{min_index})"
            pos = attr_start + length
    raise ValueError("pvads.ADS.projectOverlay Code attribute not found")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("jar", help="path to ProjectViewpointADS.jar")
    args = parser.parse_args()
    jar_path = os.path.abspath(args.jar)
    backup_path = jar_path + ".gael-lens-min-backup"
    if not os.path.isfile(jar_path):
        raise SystemExit(f"JAR not found: {jar_path}")

    with zipfile.ZipFile(jar_path, "r") as source:
        entries = [(info, source.read(info.filename)) for info in source.infolist()]
    target = "pvads/ADS.class"
    patched = False
    details = ""
    new_entries = []
    for info, content in entries:
        if info.filename == target:
            content = bytearray(content)
            _, details = locate_patch(content)
            content = bytes(content)
            patched = True
        new_entries.append((info, content))
    if not patched:
        raise SystemExit(f"{target} not found in JAR")

    if not os.path.exists(backup_path):
        shutil.copy2(jar_path, backup_path)
    fd, temp_path = tempfile.mkstemp(prefix="pvads-lens-", suffix=".jar", dir=os.path.dirname(jar_path))
    os.close(fd)
    try:
        with zipfile.ZipFile(temp_path, "w") as output:
            for info, content in new_entries:
                output.writestr(info, content)
        # Steam's Workshop directory can deny an atomic rename even when the
        # file itself is writable. The original backup is already in place,
        # so write the fully prepared archive to the existing file directly.
        with open(temp_path, "rb") as prepared, open(jar_path, "wb") as destination:
            shutil.copyfileobj(prepared, destination)
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
    print(f"Patched {jar_path}: {details}")
    print(f"Original backup: {backup_path}")


if __name__ == "__main__":
    main()
