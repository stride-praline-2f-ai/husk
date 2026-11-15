#!/usr/bin/env python3
"""Extract the returned 167 pair; omit historical [prev] lines and mirrored counts.

Usage: python METAL4-FG-167-paired.analysis.py ATTACHMENT_DIRECTORY > receipt.json
No image-quality, GPU-time or energy inference is made from these log counters.
"""
import hashlib
import json
from pathlib import Path
import re
import sys


def lines(path):
    return [line for line in path.read_text(errors="replace").splitlines()
            if "[prev]" not in line]


def select(rows, pattern):
    return [line for line in rows if re.search(pattern, line)]


def analyse(root):
    files = [root / name for name in (
        "1-husk-native-prev.log", "2-husk-prev.log",
        "3-husk-native.log", "4-husk.log")]
    result = {"schema": 1, "scope": "M9-FG-QUALITY-v1 returned167 paired modes",
              "provenance": [], "sessions": {}}
    for path in files:
        data = path.read_bytes()
        result["provenance"].append({"name": path.name, "bytes": len(data),
                                     "sha256": hashlib.sha256(data).hexdigest()})
    for mode, native, host in (("on", files[0], files[1]), ("off", files[2], files[3])):
        rows, native_rows = lines(host), lines(native)
        timings = select(rows, r"ue4 timing: cadence")
        # Host mirrors native stderr; these are independent cross-checks, not
        # additional timing samples or additional GPU completions.
        assert timings == select(native_rows, r"ue4 timing: cadence")
        begins = select(rows, r"apply begin sequence")
        completes = select(rows, r"apply complete sequence")
        identity = lambda line: re.search(r"sequence (\d+) paused ([01])", line).groups()
        assert [identity(line) for line in begins] == [identity(line) for line in completes]
        result["sessions"][mode] = {
            "primary": host.name, "native_mirror": native.name,
            "identity": select(rows, r"\[boot\].*(version|build|device|system|processors|source|built)"),
            "configuration": select(rows, r"frame generation requested|requested cap|actual guest swapchain buffer|METAL4\]|ue4 power:"),
            "timing_windows": timings,
            "wait_windows": select(rows, r"\[M4/M9 pacing-wait\]"),
            "pipeline_windows": select(rows, r"ue4 cache detail:|ue4 pipeline stall:"),
            "framegen_windows": select(rows, r"\[M9-FRAMEGEN\].*active"),
            "cache_restore_and_checkpoint": select(rows, r"ue4 cache: game initial|ue4 cache store: (loaded|pause|unchanged)"),
            "completed_lifecycle_sequences": len(completes),
            "lifecycle_sequences": completes,
            "screenshot_notifications": select(rows, r"screenshot_observed"),
            "heartbeat_tail": select(rows, r"unity: alive:")[-3:],
        }
    return result


if __name__ == "__main__":
    print(json.dumps(analyse(Path(sys.argv[1])), indent=2))
