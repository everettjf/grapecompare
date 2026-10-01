#!/usr/bin/env python3
"""Create disposable, isolated inputs for the workspace UI regression checklist."""
from pathlib import Path
import tempfile

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
print(root)
