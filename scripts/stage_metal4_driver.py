#!/usr/bin/env python3
"""Stage the pinned, published iOS Metal 4 Vulkan driver alongside MoltenVK.

This does not implement MetalFX or frame generation. Never replace either
existing driver. The upstream source/patches and full notices remain available
at the immutable release recorded in the manifest.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RELEASE = "https://github.com/playportdev/playport/releases/tag/v0.5.0"
SOURCE = "26620bf5319a0f5a5cca47cfecec797cafe45493"
MESA = "b39d173ca9369c19fda2635be6655d308067e52d"
IPA_SHA = "2620958cb60a0b452351976ec5d43fd179d1a2ada9d1cc4adef5b7b89beca04a"
BINARY_SHA = "17bba1df31d4c8eb757ce2f56fdc1f8c6af92bc5427585e33673b0c60e8ba7de"
NOTICES_SHA = "190c44319a44392874162b06268327ebcd75f80308ca3aff99392aab7f16b6f0"
PREFIX = "Payload/Playport.app/Frameworks/KosmicKrisp.framework/"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def stage(ipa, notices, root=ROOT):
    if digest(ipa) != IPA_SHA or digest(notices) != NOTICES_SHA:
        raise ValueError("Pinned Metal 4 donor IPA/notices checksum mismatch")
    with zipfile.ZipFile(ipa) as z:
        binary = z.read(PREFIX + "KosmicKrisp")
        info = plistlib.loads(z.read(PREFIX + "Info.plist"))
        if hashlib.sha256(binary).hexdigest() != BINARY_SHA:
            raise ValueError("Metal 4 driver binary checksum mismatch")
        if struct.unpack_from("<II", binary) != (0xFEEDFACF, 0x100000C):
            raise ValueError("Driver is not thin ARM64 Mach-O")
        if info.get("MinimumOSVersion") != "26.0" or info.get("CFBundleExecutable") != "KosmicKrisp":
            raise ValueError("Unexpected iOS driver metadata")
        # Copy only the pinned binary/plist; no donor app, profile, signatures,
        # symlinks, executables or arbitrary archive paths are extracted.
        parent = root / "build/ios-arm64/lib"
        parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="husk-metal4-", dir=parent)
        fw = Path(temporary.name) / "KosmicKrisp.framework"
        fw.mkdir()
        (fw / "KosmicKrisp").write_bytes(binary)
        (fw / "Info.plist").write_bytes(plistlib.dumps(info))
        (fw / "HuskMetal4Build.json").write_text(json.dumps({
            "schema": 1, "backend": "KosmicKrisp", "api": "Metal 4",
            "release": RELEASE, "source": SOURCE, "mesa": MESA,
            "ipa_sha256": IPA_SHA, "binary_sha256": BINARY_SHA,
            "minimum_ios": "26.0", "metalfx_spatial": False,
            "frame_generation": False, "husk_device_validation": "pending",
            "source_archive": RELEASE.replace("/tag/", "/download/") + "/Playport-0.5.0-source.tar",
        }, indent=2) + "\n")
    # Keep the complete upstream attribution set instead of guessing which
    # linked Mesa/compiler headers survive the released optimized binary.
    license_dir = fw / "Licenses"
    license_dir.mkdir(exist_ok=True)
    with tarfile.open(notices) as archive:
        for entry in archive.getmembers():
            path = Path(entry.name)
            if entry.isdir():
                continue
            if (not entry.isfile() or path.is_absolute() or ".." in path.parts
                    or len(path.parts) < 2 or path.parts[0] != "Licenses"
                    or entry.size > 4 * 1024 * 1024):
                raise ValueError("Unexpected donor license path/size")
            destination = fw / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.extractfile(entry).read())
    project = root / "src/app/project.yml"
    text = project.read_text()
    dependency = """      - framework: ../../build/ios-arm64/lib/KosmicKrisp.framework
        embed: true
        codeSign: true
        link: false
"""
    anchor = "      # The PS4 layer: Bachata-S4"
    if "framework: ../../build/ios-arm64/lib/KosmicKrisp.framework" not in text:
        if text.count(anchor) != 1:
            raise ValueError("Unexpected project embedding layout")
        text = text.replace(anchor, dependency + anchor)
    final = parent / "KosmicKrisp.framework"
    if final.exists():
        shutil.rmtree(final)
    shutil.move(str(fw), final)
    temporary.cleanup()
    project.write_text(text)
    return final


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("notices", type=Path)
    args = parser.parse_args()
    print(stage(args.ipa, args.notices))
