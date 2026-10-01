#!/usr/bin/env python3
"""Create disposable, isolated inputs for the workspace UI regression checklist."""
from pathlib import Path
import tempfile
import struct
import zlib

root = Path(tempfile.mkdtemp(prefix="grapecompare-workspace-ui-"))
for version in range(1, 4):
    lines = [
        f"line {line:03d}: " + (
            f"variant {version}" if line in (21, 101, 201)
            else f"unchanged context {line}"
        )
        for line in range(1, 251)
    ]
    (root / f"version{version}.txt").write_text("\n".join(lines))
for side in ("left", "right"):
    directory = root / side / "Sources"
    directory.mkdir(parents=True)
    for index in range(100):
        (directory / f"File{index:03d}.txt").write_text(f"{side} file {index}\n")
# Deterministic RGBA fixtures: visible edges, transparency, and a changed square.
def png(version):
    width, height = 240, 180
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            changed = 60 + version * 8 <= x < 130 + version * 8 and 40 <= y < 115
            raw.extend((200, 60 + version * 25, 90, 255) if changed else (50, 100, 160, 180))
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
for version in range(1, 4):
    (root / f"image{version}.png").write_bytes(png(version))
for index, side in enumerate(("left", "right"), 1):
    (root / side / "image.png").write_bytes(png(index))
    (root / side / "Sources/File003.txt").write_bytes((root / f"version{index}.txt").read_bytes())
print(root)
