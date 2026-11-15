#!/usr/bin/env python3
"""Actual driver-code contract and Dungeons settings state transitions."""
from pathlib import Path
import importlib.util,json,subprocess,sys,tempfile,unittest,struct,hashlib
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('fgcontract',ROOT/'scripts/stage_framegen_contract.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ContractFiles(unittest.TestCase):
 def test_code_hash_uses_code_bytes_and_rejects_truncated_or_missing_sections(self):
  raw=bytearray(208);struct.pack_into('<8I',raw,0,0xfeedfacf,0x100000c,0,6,1,152,0,0)
  struct.pack_into('<II',raw,32,0x19,152);struct.pack_into('<I',raw,32+64,1)
  raw[104:120]=b'__text'+bytes(10);raw[120:136]=b'__TEXT'+bytes(10);struct.pack_into('<Q',raw,144,8);struct.pack_into('<I',raw,152,200);raw[200:208]=b'newmodel'
  self.assertEqual(module.code_digest(raw),hashlib.sha256(b'newmodel').hexdigest())
  for data in [raw[:180],bytes(208),bytes(raw[:200])]:
   with self.assertRaises(ValueError):module.code_digest(data)
 def test_absent_optional_drivers_create_no_false_runtime_admission(self):
  with tempfile.TemporaryDirectory()as d:
   p=Path(d);record=module.stage(p,p/'contract.json','a'*40)
   self.assertEqual(record['model'],2);self.assertEqual(record['libraries'],{})
@unittest.skipUnless(sys.platform=='darwin','Apple Foundation/CommonCrypto and Swift required; IPA CI runs this check')
class AppleContract(unittest.TestCase):
 def test_actual_loaded_dylib_code_identity_source_and_tampered_contract(self):
  with tempfile.TemporaryDirectory()as d:
   p=Path(d);(p/'fixed.c').write_text('int fixed_entry(void){return 2;}')
   dylib=p/'FixedDriver';subprocess.run(['clang','-dynamiclib',str(p/'fixed.c'),'-o',str(dylib)],check=True)
   expected=module.code_digest(dylib.read_bytes())
   (p/'contract.json').write_text(json.dumps(dict(schema=1,model=2,app_source='a'*40,libraries={'FixedDriver':{'code_sha256':expected}})))
   (p/'wrong.json').write_text(json.dumps(dict(schema=1,model=2,app_source='a'*40,libraries={'FixedDriver':{'code_sha256':'0'*64}})))
   (p/'malformed.json').write_text('{"schema":null,"model":null}')
   (p/'old.json').write_text(json.dumps(dict(schema=1,model=1,app_source='a'*40,libraries={'FixedDriver':{'code_sha256':expected}})))
   (p/'main.m').write_text(r'''
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <assert.h>
#include <stdbool.h>
extern bool tl_fg_contract_verify(void*,const char*,const char*);
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]];
 void *lib=dlopen([root stringByAppendingPathComponent:@"FixedDriver"].fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);assert(lib);
 void *entry=dlsym(lib,"fixed_entry");assert(entry);
 const char*source="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
 assert(tl_fg_contract_verify(entry,[root stringByAppendingPathComponent:@"contract.json"].fileSystemRepresentation,source));
 assert(tl_fg_contract_verify(entry,[root stringByAppendingPathComponent:@"contract.json"].fileSystemRepresentation,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-dirty"));
 assert(!tl_fg_contract_verify(entry,[root stringByAppendingPathComponent:@"wrong.json"].fileSystemRepresentation,source));
 assert(!tl_fg_contract_verify(entry,[root stringByAppendingPathComponent:@"old.json"].fileSystemRepresentation,source));
 assert(!tl_fg_contract_verify(entry,[root stringByAppendingPathComponent:@"contract.json"].fileSystemRepresentation,"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
 assert(!tl_fg_contract_verify(entry,"/missing/contract.json",source));
 assert(!tl_fg_contract_verify(entry,[root stringByAppendingPathComponent:@"malformed.json"].fileSystemRepresentation,source));
 assert(!tl_fg_contract_verify(NULL,[root stringByAppendingPathComponent:@"contract.json"].fileSystemRepresentation,source));
 dlclose(lib);puts("PASS: actual loaded-code hash enforced; stale model/source, missing and tampered contracts refused");return 0;
}}
''')
   exe=p/'check';subprocess.run(['clang','-fobjc-arc',str(ROOT/'src/translation-layer-next/husk-tl-framegen-contract.m'),str(p/'main.m'),'-framework','Foundation','-o',str(exe)],check=True);subprocess.run([str(exe),str(p)],check=True)
 def test_actual_dungeons_choice_policy_preserves_settings_and_respects30fps(self):
  source=(ROOT/'src/app/Husk/TLAppSettings.swift').read_text()
  recognition=source.split('    func isDungeons(',1)[1].split('    func usesSharpGraphics(',1)[0]
  selects=source.split('    mutating func selectMetal4(',1)[1].split('    // DUNGEONS_SIMPLE_POLICY_BEGIN',1)[0]
  policy=source.split('    // DUNGEONS_SIMPLE_POLICY_BEGIN',1)[1].split('    // DUNGEONS_SIMPLE_POLICY_END',1)[0]
  with tempfile.TemporaryDirectory()as d:
   p=Path(d);(p/'main.swift').write_text('''
import Foundation
struct Metal4DriverCapabilities { static let current = Self(); var frameGeneration=true; var nativeArchives=true }
enum FakeEngine { case ue4,unity }
struct FakeReport { var nativeEngine:FakeEngine }
struct TLApp { var packageName:String?; var label:String; var report:FakeReport? }
struct TLAppSettings {
 enum EfficientFrameRate:Int {case cool=30,smooth=60}
 enum EfficientResolution:Int {case custom = -1, automatic=0,native=100,sharp=85}
 var frameGeneration=false,metal4Renderer=false,enhancedMetal4=false,automaticDuoProfile=true
 var efficientFrameRate=EfficientFrameRate.smooth,efficientResolution=EfficientResolution.automatic,customResolutionPercent=80
 var spatialUpscaling=true,workerScheduling=4
 func isDungeons('''+recognition+'''
 mutating func selectMetal4('''+selects+policy+'''
}
var settings=TLAppSettings();settings.efficientFrameRate = .cool
precondition(settings.isDungeons(TLApp(packageName:"com.nintendosss.spice",label:"My renamed game",report:FakeReport(nativeEngine:.ue4))))
precondition(!settings.isDungeons(TLApp(packageName:"com.example.other",label:"Minecraft Dungeons",report:FakeReport(nativeEngine:.unity))))
precondition(settings.dungeonsFrameChoice(automaticActive:true)==60)
settings.selectDungeonsFrameChoice(30,bridgeAvailable:true)
precondition(!settings.automaticDuoProfile && !settings.frameGeneration && settings.efficientFrameRate == .cool)
settings.selectDungeonsResolutionChoice(0);precondition(!settings.automaticDuoProfile)
settings.metal4Renderer=true;settings.selectDungeonsFrameChoice(120,bridgeAvailable:true)
precondition(settings.frameGeneration && settings.enhancedMetal4 && settings.dungeonsFrameChoice(automaticActive:true)==120)
settings.selectDungeonsRendererChoice(1,bridgeAvailable:true)
precondition(settings.metal4Renderer && !settings.enhancedMetal4 && !settings.frameGeneration)
settings.efficientResolution = .sharp;settings.customResolutionPercent=80
precondition(settings.dungeonsResolutionChoice == -1 && settings.dungeonsResolutionPercent == 85)
settings.selectDungeonsResolutionChoice(-1);precondition(settings.efficientResolution == .custom && settings.customResolutionPercent==85)
settings.selectDungeonsFrameChoice(60,bridgeAvailable:true);settings.selectDungeonsResolutionChoice(0)
precondition(settings.automaticDuoProfile && settings.efficientFrameRate == .smooth)
precondition(settings.spatialUpscaling && settings.workerScheduling==4)
print("PASS: actual Dungeons choice policy preserves manual scale, makes30FPS effective, combines FG/renderer controls and retains other stored preferences")
''')
   exe=p/'check';subprocess.run(['swiftc',str(p/'main.swift'),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
if __name__=='__main__':unittest.main()
