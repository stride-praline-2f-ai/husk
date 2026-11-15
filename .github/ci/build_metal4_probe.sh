#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Rebuild the exact iOS Mesa/KosmicKrisp source; never overwrite the donor.
set -euo pipefail
ROOT="${HUSK_SOURCE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
test "$(uname -s)" = Darwin || { echo 'An Apple SDK build host is required' >&2; exit 1; }
WORK="${HUSK_METAL4_BUILD_ROOT:-$ROOT/third_party/build/metal4-source}"
mkdir -p "$WORK" "$ROOT/build/logs"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
brew install llvm spirv-tools spirv-llvm-translator libclc bison flex pkgconf
LLVM_PREFIX="$(brew --prefix llvm)"
export PATH="$LLVM_PREFIX/bin:$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
export PKG_CONFIG_PATH="$(brew --prefix spirv-llvm-translator)/lib/pkgconfig:$(brew --prefix spirv-tools)/lib/pkgconfig:$(brew --prefix libclc)/share/pkgconfig:$LLVM_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
test "$(llvm-config --version | cut -d. -f1)" = 23 || { echo 'Unreviewed host LLVM major; expected 23' >&2; exit 1; }
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/python" -m pip install 'meson==1.12.1' 'ninja==1.13.0' mako pyyaml packaging ply
export PATH="$WORK/venv/bin:$PATH"
python3 - "$WORK" <<'PY'
from pathlib import Path
import sys,urllib.request,tarfile,shutil,subprocess,hashlib,json
root=Path(sys.argv[1])
records={}
for name,repo,pin in [('playport','playportdev/playport','26620bf5319a0f5a5cca47cfecec797cafe45493'),('mesa','chaotic-cx/mesa-mirror','b39d173ca9369c19fda2635be6655d308067e52d')]:
    archive=root/(name+'.tar.gz');target=root/name
    if not archive.exists():
        with urllib.request.urlopen('https://codeload.github.com/'+repo+'/tar.gz/'+pin,timeout=240)as r,archive.open('wb')as f:shutil.copyfileobj(r,f)
    records[name]={'source':pin,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
    expected={'playport':'5db214ebd14585f716b16a80428fd5baf6fc5a8f2fd222b18cb4d992718102ef','mesa':'f5e54d4cfdd3e63e975d1e8779d572711f9c6257a36f24f9b4033ba8ff77274c'}
    if records[name]['archive_sha256']!=expected[name]:raise ValueError('Pinned source archive checksum mismatch: '+name)
    if not target.exists():
        with tarfile.open(archive)as t:
            prefix=t.getmembers()[0].name.split('/')[0];t.extractall(root,filter='data')
        (root/prefix).rename(target)
marker=root/'mesa/.playport-series-applied'
if not marker.exists():
    patches=root/'playport/patches/mesa';count=0
    # git apply inside a subdirectory of the outer Husk checkout silently
    # skips paths outside that prefix. Give the dedicated source its own root.
    subprocess.run(['git','init','-q',str(root/'mesa')],check=True)
    for line in (patches/'series').read_text().splitlines():
        name=line.split('#')[0].strip()
        if name:subprocess.run(['git','apply',str(patches/name)],cwd=root/'mesa',check=True);count+=bool(name)
    marker.write_text(str(count))
if 'KK_EXPERIMENTAL(CMD_RETIRE)' not in (root/'mesa/src/kosmickrisp/vulkan/kk_queue.c').read_text():raise ValueError('Pinned upstream series was not applied')
if 'playportReadableSource' not in (root/'mesa/src/kosmickrisp/bridge/mtl_bridge.m').read_text():raise ValueError('Pinned Metal WSI patch missing')
(root/'source-inputs.json').write_text(json.dumps(records,indent=2)+'\n')
# Upstream's Linux cross compiler does not reject this macOS-only property.
# Apple's iOS SDK does: retain its platform semantics with an explicit guard.
p=root/'mesa/src/vulkan/wsi/wsi_common_metal_layer.m';s=p.read_text()
if '#if !TARGET_OS_IPHONE /* Husk SDK guard */' not in s:
    needle='metal_layer.displaySyncEnabled = !enable_immediate;'
    if s.count(needle)!=2:raise ValueError('Unexpected WSI display-sync anchors')
    p.write_text(s.replace(needle,'\n#if !TARGET_OS_IPHONE /* Husk SDK guard */\n      '+needle+'\n#endif'))
PY
if [ "${HUSK_METAL4_UPSTREAM_ONLY:-0}" != 1 ]; then
    python3 "$ROOT/scripts/prepare_metal4_source.py" "$WORK/mesa"
    # Check public SDK signatures before compiling the full NIR/driver tree.
    xcrun --sdk iphoneos clang++ -target arm64-apple-ios26.0 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -std=c++17 -fblocks -fno-objc-arc -fsyntax-only "$WORK/mesa/src/kosmickrisp/bridge/HuskMetal4Compiler.mm" "$WORK/mesa/src/kosmickrisp/bridge/HuskMetal4Framegen.mm"
    python3 "$ROOT/tests/translation-layer/test_metal4_components.py" -v
fi
export MACOSX_DEPLOYMENT_TARGET=26.0
COMMON=(-Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dzstd=disabled -Dbuildtype=release -Dwrap_mode=nofallback)
CC=clang CXX=clang++ OBJC=clang meson setup "$WORK/host" "$WORK/mesa" "${COMMON[@]}" -Dplatforms= -Dllvm=enabled
ninja -C "$WORK/host" -j 3 src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2 src/kosmickrisp/clc/kk_clc
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
APPLE_CC="$(xcrun --sdk iphoneos --find clang)"
APPLE_CXX="$(xcrun --sdk iphoneos --find clang++)"
cat > "$WORK/ios.cross" <<EOF
[binaries]
c = ['$APPLE_CC', '-target', 'arm64-apple-ios26.0', '-isysroot', '$SDK']
cpp = ['$APPLE_CXX', '-target', 'arm64-apple-ios26.0', '-isysroot', '$SDK']
objc = ['$APPLE_CC', '-target', 'arm64-apple-ios26.0', '-isysroot', '$SDK']
objcpp = ['$APPLE_CXX', '-target', 'arm64-apple-ios26.0', '-isysroot', '$SDK']
ar = 'ar'
strip = 'strip'
pkg-config = 'false'
[properties]
needs_exe_wrapper = true
[host_machine]
system = 'darwin'
subsystem = 'ios'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
EOF
cat > "$WORK/host-tools.native" <<EOF
[binaries]
mesa_clc = '$WORK/host/src/compiler/clc/mesa_clc'
vtn_bindgen2 = '$WORK/host/src/compiler/spirv/vtn_bindgen2'
kk_clc = '$WORK/host/src/kosmickrisp/clc/kk_clc'
EOF
meson setup "$WORK/ios" "$WORK/mesa" --cross-file "$WORK/ios.cross" --native-file "$WORK/host-tools.native" "${COMMON[@]}" -Dplatforms=macos -Dllvm=disabled -Dexpat=disabled -Dmesa-clc=system -Dprecomp-compiler=system
ninja -C "$WORK/ios" -j 3 src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib
OUT="$ROOT/build/ios-arm64/lib/HuskKosmicKrisp.framework"
mkdir -p "$OUT"
cp "$WORK/ios/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib" "$OUT/HuskKosmicKrisp"
install_name_tool -id @rpath/HuskKosmicKrisp.framework/HuskKosmicKrisp "$OUT/HuskKosmicKrisp"
cp "$WORK/source-inputs.json" "$OUT/HuskMetal4Source.json"
python3 "$WORK/playport/build/check-macho-imports.py" --sdk "$SDK" --platform ios --minos 26.0 --exports vkGetInstanceProcAddr,vkGetDeviceProcAddr "$OUT/HuskKosmicKrisp"
if [ "${HUSK_METAL4_UPSTREAM_ONLY:-0}" != 1 ]; then
    xcrun nm -gU "$OUT/HuskKosmicKrisp" > "$ROOT/build/logs/metal4-source-exports.txt"
    for symbol in ArchiveConfigure ArchiveSnapshot ArchivePrepare ArchiveForget FramegenConfigure FramegenSnapshot FramegenPause Metal4Checkpoint; do
        grep -E "_vkHusk${symbol}$" "$ROOT/build/logs/metal4-source-exports.txt"
    done
    python3 - "$ROOT" "$WORK" "$OUT" <<'PY'
from pathlib import Path
import sys,json,plistlib,subprocess,hashlib,struct,shutil
root,work,out=map(Path,sys.argv[1:]);patch=json.loads((work/'mesa/HuskMetal4Patch.json').read_text())
b=(out/'HuskKosmicKrisp').read_bytes();p=32;code=None
assert struct.unpack_from('<II',b)==(0xfeedfacf,0x100000c)
for _ in range(struct.unpack_from('<I',b,16)[0]):
    cmd,n=struct.unpack_from('<II',b,p)
    if cmd==0x19:
        for i in range(struct.unpack_from('<I',b,p+64)[0]):
            q=p+72+i*80
            if b[q:q+16].split(b'\0')[0]==b'__text'and b[q+16:q+32].split(b'\0')[0]==b'__TEXT':
                size=struct.unpack_from('<Q',b,q+40)[0];offset=struct.unpack_from('<I',b,q+48)[0];code=hashlib.sha256(b[offset:offset+size]).hexdigest()
    p+=n
assert code
meta={'schema':2,'backend':'KosmicKrisp','api':'Metal 4','source':patch['playport'],'mesa':patch['mesa'],'husk_bridge_abi':1,'native_archive_abi':2,'frame_generation':True,'metalfx_spatial':False,'minimum_ios':'26.0','compiler_contract':'husk-kk-native-v1','patch_sha256':patch['patch_sha256'],'code_sha256':code,'binary_sha256_before_signing':hashlib.sha256(b).hexdigest(),'sdk_build':subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-build-version'],text=True).strip(),'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),'host_llvm':subprocess.check_output(['llvm-config','--version'],text=True).strip()}
(out/'HuskMetal4Build.json').write_text(json.dumps(meta,indent=2)+'\n')
info={'CFBundleExecutable':'HuskKosmicKrisp','CFBundleName':'HuskKosmicKrisp','CFBundleIdentifier':'com.husk.experimental.KosmicKrisp','CFBundlePackageType':'FMWK','CFBundleShortVersionString':'1.0','CFBundleVersion':patch['patch_sha256'][:12],'CFBundleSupportedPlatforms':['iPhoneOS'],'MinimumOSVersion':'26.0'}
(out/'Info.plist').write_bytes(plistlib.dumps(info))
notices=root/'build/ios-arm64/lib/KosmicKrisp.framework/Licenses'
if notices.exists():shutil.copytree(notices,out/'Licenses',dirs_exist_ok=True)
(out/'HuskSourceNotice.txt').write_text('Husk source bridge: GPL-2.0-or-later. Colour-flow source: Apache-2.0. Mesa and full upstream attribution retained in Licenses and the companion KosmicKrisp framework.\nSource: https://github.com/stride-praline-2f-ai/husk ; upstream: https://github.com/playportdev/playport/tree/'+patch['playport']+'\n')
project=root/'src/app/project.yml'
if project.exists():
    text=project.read_text();dependency='      - framework: ../../build/ios-arm64/lib/HuskKosmicKrisp.framework\n        embed: true\n        codeSign: true\n        link: false\n'
    if 'framework: ../../build/ios-arm64/lib/HuskKosmicKrisp.framework'not in text:
        anchor='      # The PS4 layer: Bachata-S4'
        if text.count(anchor)!=1:raise ValueError('Unexpected source driver embedding layout')
        project.write_text(text.replace(anchor,dependency+anchor))
print('Source bridge contract, ARM64 code, eight exports and metadata verified')
PY
fi
echo 'Pinned source-built iOS Metal4 driver passed import/export validation'
