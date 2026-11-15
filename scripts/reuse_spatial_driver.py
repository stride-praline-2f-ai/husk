#!/usr/bin/env python3
"""Reuse an independently verified arm64 driver only for an identical compiler/patch contract."""
import hashlib,json,shutil,sys,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ZIP_SHA256='c47037417ac9b9a08b643cc0df97e7666fcb188435f90df9c95710796a6c8ccc'
COMPAT='a734100aa2a773b1e782c33b541593c02e7bba35aa28a5524ea30f2025202c50'
PIN='db66022459ffb663aa2b50f6b018bc2e124f5edf'
INPUTS=['patches/metalfx/HuskDisplay.inc','src/translation-layer-next/husk-tl-display.h','scripts/prepare_spatial_driver.py','patches/metalfx/HuskSpatial.inc','patches/metalfx/HuskSpatialDriver.h','src/translation-layer-next/husk-tl-spatial.h','patches/metalfx/HuskArchive.inc','src/translation-layer-next/husk-tl-native-archive.h','patches/metalfx/HuskFramegen.inc','patches/metalfx/HuskFramegen.metal','src/translation-layer-next/husk-tl-framegen.h','patches/metalfx/HuskFGCapture.inc']
def stage(archive):
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=ZIP_SHA256:raise SystemExit('Verified driver archive checksum mismatch')
    digest=hashlib.sha256()
    for name in INPUTS:digest.update((ROOT/name).read_bytes())
    with zipfile.ZipFile(archive)as z:
        entries=z.infolist()
        if len(entries)>128 or sum(i.file_size for i in entries)>64*1024*1024:raise SystemExit('Driver archive exceeds bounds')
        if any(not i.filename.startswith('HuskMoltenVK.framework/') or '..'in Path(i.filename).parts for i in entries):raise SystemExit('Unexpected driver archive path')
        if z.testzip()is not None:raise SystemExit('Driver archive CRC mismatch')
        manifest=json.loads(z.read('HuskMoltenVK.framework/HuskSpatialBuild.json'))
        if (manifest.get('upstream_commit')!=PIN or manifest.get('native_archive_abi')!=2 or manifest.get('native_archive_cache_schema')!=2 or manifest.get('native_archive_compatibility_id')!=COMPAT or manifest.get('husk_spatial_patch_sha256')!=digest.hexdigest()):
            raise SystemExit('Driver source/compiler contract changed; rebuild driver instead of reusing')
        destination=ROOT/'build/ios-arm64/lib';destination.mkdir(parents=True,exist_ok=True)
        framework=destination/'HuskMoltenVK.framework'
        if framework.exists():shutil.rmtree(framework)
        z.extractall(destination)
    project=ROOT/'src/app/project.yml';text=project.read_text()
    anchor='      # The PS4 layer: Bachata-S4'
    dependency='''      - framework: ../../build/ios-arm64/lib/HuskMoltenVK.framework
        embed: true
        codeSign: true
        link: false
'''
    if 'framework: ../../build/ios-arm64/lib/HuskMoltenVK.framework'not in text:
        if text.count(anchor)!=1:raise SystemExit('Unexpected project embedding layout')
        project.write_text(text.replace(anchor,dependency+anchor))
    print('Reused verified arm64 graphics driver: exact patch digest, MoltenVK pin, ABI2/schema2/compiler contract match')
if __name__=='__main__':stage(Path(sys.argv[1]))
