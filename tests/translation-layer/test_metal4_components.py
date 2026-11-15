#!/usr/bin/env python3
"""Actual Metal4 wrapper control contracts; Apple SDK required."""
from pathlib import Path
import subprocess,sys,tempfile,unittest,importlib.util
ROOT=Path(__file__).resolve().parents[2]
@unittest.skipUnless(sys.platform=='darwin','Apple Metal SDK required; native source-build CI runs this check')
class Metal4Components(unittest.TestCase):
    def test_production_compiler_cache_epoch_and_persistence_contract(self):
        with tempfile.TemporaryDirectory()as d:
            root=Path(d)
            (root/'HuskNativeArchiveABI.h').write_bytes((ROOT/'src/translation-layer-next/husk-tl-native-archive.h').read_bytes())
            exe=root/'contract'
            subprocess.run(['xcrun','--sdk','macosx','clang++','-std=c++17','-mmacosx-version-min=26.0','-fno-objc-arc','-fblocks','-I',str(root),'-I',str(ROOT/'patches/metal4'),str(ROOT/'tests/translation-layer/metal4_compiler_contract.mm'),'-framework','Foundation','-framework','Metal','-o',str(exe)],check=True)
            subprocess.run([str(exe),str(root/'owned-cache')],check=True,timeout=20)
    def test_production_framegen_feedback_leases_and_epoch_retirement(self):
        with tempfile.TemporaryDirectory()as d:
            root=Path(d)
            spec=importlib.util.spec_from_file_location('metal4patch',ROOT/'scripts/prepare_metal4_source.py')
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            (root/'HuskFramegen.inc').write_text(module.framegen_include())
            (root/'HuskFramegenABI.h').write_bytes((ROOT/'src/translation-layer-next/husk-tl-framegen.h').read_bytes())
            shader=(ROOT/'patches/metalfx/HuskFramegen.metal').read_text()
            (root/'HuskFramegenShader.inc').write_text('static const char *huskFramegenShader=R"HUSKFG('+shader+')HUSKFG";')
            exe=root/'contract'
            subprocess.run(['xcrun','--sdk','macosx','clang++','-std=c++17','-mmacosx-version-min=26.0','-fno-objc-arc','-fblocks','-I',str(root),'-I',str(ROOT/'patches/metal4'),str(ROOT/'tests/translation-layer/metal4_framegen_contract.mm'),'-framework','Foundation','-framework','Metal','-framework','QuartzCore','-framework','AppKit','-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True,timeout=20)
if __name__=='__main__':unittest.main()
