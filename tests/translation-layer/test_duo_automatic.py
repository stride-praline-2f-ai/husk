#!/usr/bin/env python3
"""Actual launch policy and settings decode: physical pixels, guards and opt-out."""
from pathlib import Path
import shutil,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
@unittest.skipUnless(shutil.which('swiftc'),'Apple Swift policy/settings check is required on the Mac runner')
class DuoAutomaticTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup);p=Path(cls.tmp.name)
  settings=(ROOT/'src/app/Husk/TLAppSettings.swift').read_text().split('// MARK: - The settings page')[0].replace('import SwiftUI','').replace('import UIKit','')
  (p/'Settings.swift').write_text('import Foundation\nimport CoreGraphics\n'+settings)
  (p/'Facades.swift').write_text('''import Foundation
import CoreGraphics
struct FakeReport { var nativeEngine: FakeEngine }
enum FakeEngine { case ue4, unity }
struct TLApp { var label: String; var packageName: String?; var report: FakeReport? }
enum TranslationLayer { static let root = URL(fileURLWithPath: "/tmp/unused-duo-settings") }
enum Idiom { case pad, phone }
class UIDevice { static let current=UIDevice(); var userInterfaceIdiom=Idiom.phone }
class UIScreen { static let main=UIScreen(); var bounds=CGRect(x:0,y:0,width:669,height:951); var scale:CGFloat=3; var nativeBounds=CGRect(x:0,y:0,width:1878,height:2670); var phone=true }
extension DuoDisplayPolicy { @MainActor static func metrics(screen:UIScreen)->Metrics { Metrics(pointWidth:Double(screen.bounds.width),pointHeight:Double(screen.bounds.height),nativeWidth:Double(screen.nativeBounds.width),nativeHeight:Double(screen.nativeBounds.height),phoneHardware:screen.phone) } }
@_silgen_name("tl_ue4_resolution_fraction") func tl_ue4_resolution_fraction(_ w:Int32,_ h:Int32,_ tablet:Bool,_ percent:Int32)->Double
''')
  (p/'main.swift').write_text(r'''import Foundation
import CoreGraphics
@main struct PolicyTest { @MainActor static func main() throws {
let mode=CommandLine.arguments[1]
let portrait=DuoDisplayPolicy.Metrics(pointWidth:669,pointHeight:951,nativeWidth:1878,nativeHeight:2670,phoneHardware:true)
let landscape=DuoDisplayPolicy.Metrics(pointWidth:951,pointHeight:669,nativeWidth:2670,nativeHeight:1878,phoneHardware:true)
func target(_ m:DuoDisplayPolicy.Metrics)->(Int,Int) { let scale=m.scale()!;return (Int((max(m.pointWidth,m.pointHeight)*scale).rounded()) & ~7,Int((min(m.pointWidth,m.pointHeight)*scale).rounded()) & ~7) }
let game=TLApp(label:"Minecraft Dungeons",packageName:"com.nintendosss.spice",report:FakeReport(nativeEngine:.ue4))
if mode=="geometry" {
 assert(portrait.isInner && landscape.isInner)
 let (w,h)=target(landscape);assert(w==1816 && h==1280)
 assert(target(portrait).0==w && target(portrait).1==h)
 assert((w*DuoDisplayPolicy.inputPercent/100) & ~7==1448 && (h*DuoDisplayPolicy.inputPercent/100) & ~7==1024)
 assert(portrait.scale(percent:100)! < 3)
} else if mode=="a20" {
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 Pro GPU",cpuCount:6)==2)
 assert(DuoDisplayPolicy.workerPolicy(gpuName:"Apple A20 Pro GPU",cpuCount:6)==4)
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 GPU",cpuCount:6,performanceCores:2,efficiencyCores:4)==2)
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 Pro GPU",cpuCount:6,performanceCores:1,efficiencyCores:5)==1)
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 GPU",cpuCount:6)==0) // unknown split has no model fallback
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 Pro GPU",cpuCount:6,performanceCores:2,efficiencyCores:3)==0)
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 Pro GPU",cpuCount:6,enabled:false,performanceCores:2,efficiencyCores:4)==0)
 assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple M4 GPU",cpuCount:10,performanceCores:4,efficiencyCores:6)==0)

 for name in ["Apple M4 GPU","Apple A19 Pro GPU","Apple GPU",""] {
  assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:name,cpuCount:6)==0)
  assert(DuoDisplayPolicy.workerPolicy(gpuName:name,cpuCount:6)==2)
 }
 for count in [-1,0,5,8] {assert(DuoDisplayPolicy.fastWorkerBudget(gpuName:"Apple A20 Pro GPU",cpuCount:count)==0)}
 assert(DuoDisplayPolicy.workerPolicy(gpuName:"Apple A20 Pro GPU",cpuCount:6,enabled:false)==2)
} else if mode=="guards" {
 var m=portrait;m.phoneHardware=false;assert(!m.isInner && m.scale()==nil)
 m=portrait;m.nativeWidth=1398;m.nativeHeight=2034;assert(!m.isInner)
 m=portrait;m.nativeWidth=2064;m.nativeHeight=2752;assert(!m.isInner)
 for invalid in [0.0,-1.0,Double.nan,Double.infinity,20000] {m=portrait;m.pointWidth=invalid;assert(!m.isInner && m.scale()==nil)}
} else if mode=="admission" {
 assert(portrait.automatic(enabled:true,efficientDungeons:true,windowed:false))
 assert(!portrait.automatic(enabled:false,efficientDungeons:true,windowed:false))
 assert(!portrait.automatic(enabled:true,efficientDungeons:false,windowed:false))
 assert(!portrait.automatic(enabled:true,efficientDungeons:true,windowed:true))
 assert(DuoDisplayPolicy.fps==60 && DuoDisplayPolicy.worker==2 && DuoDisplayPolicy.submission==0)
} else if mode=="decode" {
 let original=Data("{\"spatialUpscaling\":false,\"efficientResolution\":65,\"customResolutionPercent\":71}".utf8)
 let settings=try JSONDecoder().decode(TLAppSettings.self,from:original)
 assert(!settings.metal4Renderer && !settings.frameGeneration && settings.automaticDuoProfile && settings.a20EfficiencyWorkers && settings.sharedMemoryReserve && !settings.spatialUpscaling && settings.efficientResolution == .performance && settings.customResolutionPercent==71)
 assert(settings.supportsDuoAutomatic(for:game))
 assert(!settings.supportsDuoAutomatic(for:TLApp(label:"Other game",packageName:nil,report:FakeReport(nativeEngine:.ue4))))
 var manual=settings;manual.metal4Renderer=true;manual.frameGeneration=true;manual.automaticDuoProfile=false;manual.a20EfficiencyWorkers=false;manual.sharedMemoryReserve=false
 let roundtrip=try JSONDecoder().decode(TLAppSettings.self,from:JSONEncoder().encode(manual))
 assert(roundtrip.metal4Renderer && !roundtrip.frameGeneration && !roundtrip.automaticDuoProfile && !roundtrip.a20EfficiencyWorkers && !roundtrip.sharedMemoryReserve && roundtrip.customResolutionPercent==71 && !roundtrip.spatialUpscaling)
 var chosen=TLAppSettings();chosen.selectFrameGeneration(true);assert(chosen.frameGeneration && !chosen.metal4Renderer)
 chosen.selectMetal4(true);assert(chosen.metal4Renderer && !chosen.frameGeneration)
 chosen.selectFrameGeneration(true);assert(chosen.frameGeneration && !chosen.metal4Renderer)
 chosen.selectFrameGeneration(false);assert(!chosen.frameGeneration && !chosen.metal4Renderer)
 for m4 in [false,true] {for fg in [false,true] {assert(DuoDisplayPolicy.usesFrameGeneration(metal4:m4,requested:fg)==(fg && !m4))}}
} else if mode=="metal4-bridge" {
 var json:[String:Any] = ["schema":2,"husk_bridge_abi":1,"native_archive_abi":2,"mesa":"b39d173ca9369c19fda2635be6655d308067e52d","source":"26620bf5319a0f5a5cca47cfecec797cafe45493","frame_generation":true]
 func read(_ value:[String:Any],_ binary:Bool=true)->Metal4DriverCapabilities {Metal4DriverCapabilities.read(try! JSONSerialization.data(withJSONObject:value),binaryAvailable:binary)}
 assert(read(json).frameGeneration && read(json).nativeArchives && read(json,false) == .init())
 for key in ["schema","husk_bridge_abi","native_archive_abi"] {var invalid=json;invalid[key]=99;assert(read(invalid) == .init())}
 var invalid=json;invalid["schema"]=true;assert(read(invalid) == .init())
 invalid=json;invalid["source"]="wrong";assert(read(invalid) == .init())
 invalid=json;invalid.removeValue(forKey:"frame_generation");assert(read(invalid) == .init())
 assert(Metal4DriverCapabilities.read(Data("broken".utf8),binaryAvailable:true) == .init())
 var selected=TLAppSettings();assert(!selected.enhancedMetal4)
 selected.selectMetal4(true,bridgeAvailable:true);selected.selectFrameGeneration(true,bridgeAvailable:true)
 assert(selected.metal4Renderer && selected.frameGeneration && selected.enhancedMetal4)
 assert(DuoDisplayPolicy.usesFrameGeneration(metal4:true,requested:true,metal4Bridge:true))
 selected.selectEnhancedMetal4(false,bridgeAvailable:true);assert(selected.metal4Renderer && !selected.frameGeneration && !selected.enhancedMetal4)
 selected.selectEnhancedMetal4(true,bridgeAvailable:false);assert(!selected.enhancedMetal4)
 selected.selectFrameGeneration(true,bridgeAvailable:false);assert(!selected.metal4Renderer && selected.frameGeneration)
} else if mode=="rate" {
 var rate=FrameGenerationRate();assert(rate.sample(time:1,real:10,generated:9,resets:0)==nil)
 assert(rate.sample(time:2,real:38,generated:36,resets:0)==55)
 assert(rate.sample(time:3,real:66,generated:64,resets:0)==56)
 assert(rate.sample(time:4,real:94,generated:92,resets:1)==nil)
 assert(rate.sample(time:10,real:94,generated:92,resets:1)==nil)
 assert(rate.sample(time:11,real:94,generated:92,resets:1)==0)
 assert(rate.sample(time:12,real:1,generated:0,resets:1)==nil)
 assert(rate.sample(time:Double.nan,real:1,generated:0,resets:1)==nil)
 assert(rate.sample(time:13,real:1,generated:0,resets:1)==nil)
 rate.reset();assert(rate.sample(time:14,real:1,generated:0,resets:1)==nil)
} else if mode=="duo-settings" {
 var settings=TLAppSettings();settings.efficientResolution = .native
 UIDevice.current.userInterfaceIdiom = .pad // inner-screen UI idiom must not accidentally select the iPad budget
 assert(settings.duoAutomaticActive(for:game))
 let scale=settings.renderScale(for:game);assert(abs(Double(scale)-portrait.scale()!)<0.00001)
 assert(settings.fullscreenResolutionEstimate(for:game)=="1816 × 1280")
 settings.automaticDuoProfile=false;assert(!settings.duoAutomaticActive(for:game))
 assert(settings.renderScale(for:game)>scale && settings.renderScale(for:game)<3)
} else if mode=="m4" {
 UIScreen.main.bounds=CGRect(x:0,y:0,width:1376,height:1032);UIScreen.main.scale=2;UIScreen.main.nativeBounds=CGRect(x:0,y:0,width:2752,height:2064);UIScreen.main.phone=false
 UIDevice.current.userInterfaceIdiom = .pad
 let settings=TLAppSettings();assert(!settings.duoAutomaticActive(for:game))
 assert(settings.fullscreenResolutionEstimate(for:game)=="2128 × 1600")
 assert(!settings.spatialUpscaling && settings.efficientFrameRate == .smooth && settings.workerScheduling == .balanced)
} else {fatalError("unknown case")}
print("PASS",mode)
}}
''')
  subprocess.run(['cc','-c',str(ROOT/'src/translation-layer-next/husk-tl-ue4-graphics.c'),'-o',str(p/'graphics.o')],check=True)
  cls.exe=p/'test';subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(ROOT/'src/app/Husk/HuskExecutionOptions.swift'),str(ROOT/'src/app/Husk/DuoDisplayPolicy.swift'),str(ROOT/'src/app/Husk/FrameGenerationRate.swift'),str(ROOT/'src/app/Husk/Metal4DriverCapabilities.swift'),str(p/'Facades.swift'),str(p/'Settings.swift'),str(p/'main.swift'),str(p/'graphics.o'),'-o',str(cls.exe)],check=True)
 def case(self,name):subprocess.run([str(self.exe),name],check=True)
 def test_two_stage_geometry_uses_physical_panel_and_is_orientation_independent(self):self.case('geometry')
 def test_a20_runtime_match_fallback_and_independent_worker_opt_out(self):self.case('a20')
 def test_outer_unknown_nonphone_and_invalid_metrics_stay_out(self):self.case('guards')
 def test_opt_out_window_and_other_game_do_not_apply_profile(self):self.case('admission')
 def test_old_settings_migrate_without_overwriting_manual_values_and_opt_out_roundtrips(self):self.case('decode')
 def test_duo_phone_budget_survives_tablet_ui_idiom_and_manual_native_uses_panel_pixels(self):self.case('duo-settings')
 def test_m4_baseline_and_default_scaler_are_unchanged(self):self.case('m4')
 def test_verified_source_bridge_admission_and_explicit_combined_selection(self):self.case('metal4-bridge')
 def test_output_rate_uses_actual_callbacks_and_rejects_resets_and_gaps(self):self.case('rate')
if __name__=='__main__':unittest.main()
