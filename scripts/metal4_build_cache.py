#!/usr/bin/env python3
"""Exact source/toolchain-keyed cache for the separate Metal4 framework."""
from pathlib import Path
import hashlib,importlib.util,json,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
patch=module('metal4patch',ROOT/'scripts/prepare_metal4_source.py')
cache=module('componentcache',ROOT/'scripts/ipa_build_cache.py')
def source_digest():
    h=hashlib.sha256()
    for name in patch.INPUTS:h.update(name.encode()+b'\0'+(ROOT/name).read_bytes()+b'\0')
    return h.hexdigest()
def key():
    platform=subprocess.check_output(['xcodebuild','-version'],text=True)+subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-build-version'],text=True)
    names=patch.INPUTS+['scripts/build_metal4_source_ios.sh','scripts/metal4_build_cache.py']
    return cache.digest_files(ROOT,names,'metal4-source-v1/host-llvm23/'+platform)
def embed():
    project=ROOT/'src/app/project.yml';text=project.read_text()
    if 'framework: ../../build/ios-arm64/lib/HuskKosmicKrisp.framework'not in text:
        anchor='      # The PS4 layer: Bachata-S4'
        if text.count(anchor)!=1:raise ValueError('Unexpected source framework layout')
        text=text.replace(anchor,'      - framework: ../../build/ios-arm64/lib/HuskKosmicKrisp.framework\n        embed: true\n        codeSign: true\n        link: false\n'+anchor);project.write_text(text)
def run(action,expected):
    saved=ROOT/'build/cache/metal4';target=ROOT/'build/ios-arm64/lib/HuskKosmicKrisp.framework'
    if action=='restore':
        try:
            cache.validate(saved,expected);meta=json.loads((saved/'HuskMetal4Build.json').read_text())
            if meta['schema']!=2 or meta['patch_sha256']!=source_digest() or meta['husk_bridge_abi']!=1 or meta['native_archive_abi']!=2 or meta['frame_generation']is not True:raise ValueError('Metal4 bridge contract mismatch')
            if target.exists():shutil.rmtree(target)
            shutil.copytree(saved,target);(target/'.husk-cache.json').unlink();embed()
            print('Verified source-matched Metal4 framework component cache hit');return True
        except (OSError,KeyError,ValueError)as e:print('Metal4 source cache miss:',e);return False
    if action!='save':raise ValueError('Unknown source cache action')
    meta=json.loads((target/'HuskMetal4Build.json').read_text());assert meta['patch_sha256']==source_digest()
    if saved.exists():shutil.rmtree(saved)
    shutil.copytree(target,saved);cache.seal(saved,expected);return True
if __name__=='__main__':
    if sys.argv[1]=='key':print('metal4='+key())
    else:raise SystemExit(0 if run(sys.argv[1],sys.argv[2])else 1)
