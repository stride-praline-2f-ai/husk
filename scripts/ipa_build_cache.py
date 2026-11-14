#!/usr/bin/env python3
"""Content-keyed build components. Cache bytes are checked again before staging."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'husk-components-v1'

def digest_files(root, paths, platform):
    h = hashlib.sha256((VERSION + '\n' + platform).encode())
    for name in sorted(set(paths)):
        p = root / name
        h.update(name.encode() + b'\0' + p.read_bytes() + b'\0')
    return h.hexdigest()

def keys(root, platform):
    spec = importlib.util.spec_from_file_location('reuse', root / 'scripts/reuse_spatial_driver.py')
    reuse = importlib.util.module_from_spec(spec); spec.loader.exec_module(reuse)
    driver = reuse.INPUTS + ['scripts/build_spatial_moltenvk_ios.sh', 'scripts/reuse_spatial_driver.py', 'scripts/ipa_build_cache.py']
    driver += [str(p.relative_to(root)) for p in (root / 'patches').glob('husk-spirv-cross-*.patch')]
    java = [str(p.relative_to(root)) for p in (root / 'src/java-framework').rglob('*') if p.is_file() and p.suffix in {'.java', '.py', '.sh'} and '__pycache__' not in p.parts]
    java += ['scripts/build_java_framework_for_ipa.sh', 'scripts/ipa_build_cache.py', 'tests/java-framework/ProgressBarContract.java', 'tests/java-framework/run_progress_bar.py']
    return {'driver': digest_files(root, driver, platform), 'java': digest_files(root, java, platform),
            'tools': hashlib.sha256((VERSION + platform).encode()).hexdigest()}

def file_hashes(root):
    files = {}
    for p in sorted(root.rglob('*')):
        if p.is_symlink(): raise ValueError('Component cache contains a symlink')
        if p.is_file() and p != root / '.husk-cache.json':
            files[str(p.relative_to(root))] = hashlib.sha256(p.read_bytes()).hexdigest()
    if not files: raise ValueError('Empty component cache')
    return files

def seal(root, key):
    receipt = {'version': VERSION, 'key': key, 'files': file_hashes(root)}
    (root / '.husk-cache.json').write_text(json.dumps(receipt, sort_keys=True) + '\n')

def validate(root, key):
    if root.is_symlink(): raise ValueError('Component root is a symlink')
    r = json.loads((root / '.husk-cache.json').read_text())
    if r['version'] != VERSION or r['key'] != key or r['files'] != file_hashes(root):
        raise ValueError('Component cache key or contents changed')
    return r

def embed_driver(root):
    p = root / 'src/app/project.yml'; text = p.read_text()
    dependency = '''      - framework: ../../build/ios-arm64/lib/HuskMoltenVK.framework
        embed: true
        codeSign: true
        link: false
'''
    if 'framework: ../../build/ios-arm64/lib/HuskMoltenVK.framework' not in text:
        anchor = '      # The PS4 layer: Bachata-S4'
        if text.count(anchor) != 1: raise ValueError('Unexpected project embedding layout')
        p.write_text(text.replace(anchor, dependency + anchor))

def component(root, kind, action, key):
    cache = root / 'build/cache' / kind
    target = root / ('build/ios-arm64/lib/HuskMoltenVK.framework' if kind == 'driver' else 'build/java-runtime')
    java_names = ['husk-framework.dex', 'husk-framework-core.dex', 'husk-framework-build.json']
    if action == 'save':
        if cache.exists(): shutil.rmtree(cache)
        cache.mkdir(parents=True)
        if kind == 'driver': shutil.copytree(target, cache / target.name)
        else:
            for name in java_names: shutil.copy2(target / name, cache / name)
        seal(cache, key)
        return True
    try:
        validate(cache, key)
        if kind == 'driver':
            staged = cache / target.name
            manifest = json.loads((staged / 'HuskSpatialBuild.json').read_text())
            spec = importlib.util.spec_from_file_location('reuse', root / 'scripts/reuse_spatial_driver.py')
            reuse = importlib.util.module_from_spec(spec); spec.loader.exec_module(reuse)
            digest = hashlib.sha256()
            for name in reuse.INPUTS: digest.update((root / name).read_bytes())
            if manifest.get('husk_spatial_patch_sha256') != digest.hexdigest() or manifest.get('upstream_commit') != reuse.PIN or manifest.get('native_archive_compatibility_id') != reuse.COMPAT or manifest.get('native_archive_abi') != 2 or manifest.get('native_archive_cache_schema') != 2:
                raise ValueError('Driver compiler contract mismatch')
            subprocess.run(['xcrun', 'lipo', '-verify_arch', 'arm64', str(staged / 'HuskMoltenVK')], check=True)
            if target.exists(): shutil.rmtree(target)
            shutil.copytree(staged, target)
            embed_driver(root)
        else:
            receipt = json.loads((cache / 'husk-framework-build.json').read_text())
            source_hash = hashlib.sha256((root / 'src/java-framework/src/android/widget/ProgressBar.java').read_bytes()).hexdigest()
            if receipt.get('progressbar_source_sha256') != source_hash: raise ValueError('Java source receipt mismatch')
            for name in java_names[:2]:
                data = (cache / name).read_bytes(); expected = receipt['files'][name]
                if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']: raise ValueError('Java DEX receipt mismatch')
            donor = root / 'build/graphics-base/Payload/Husk.app/java-runtime'
            shutil.copytree(donor, target, dirs_exist_ok=True)
            for name in java_names: shutil.copy2(cache / name, target / name)
        print('Verified component cache hit:', kind)
        return True
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e:
        print('Component cache miss:', kind, str(e), file=sys.stderr)
        return False

def main():
    if sys.argv[1] == 'keys':
        platform = subprocess.check_output(['xcodebuild', '-version'], text=True) + subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-build-version'], text=True) + os.uname().machine
        for name, key in keys(ROOT, platform).items(): print(name + '=' + key)
    else:
        action, kind, key = sys.argv[1:4]
        if action not in ['restore', 'save'] or kind not in ['driver', 'java']: raise SystemExit('Invalid component operation')
        raise SystemExit(0 if component(ROOT, kind, action, key) else 1)

if __name__ == '__main__': main()
