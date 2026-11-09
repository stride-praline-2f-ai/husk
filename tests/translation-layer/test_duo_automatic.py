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
 assert(settings.automaticDuoProfile && settings.a20EfficiencyWorkers && !settings.spatialUpscaling && settings.efficientResolution == .performance && settings.customResolutionPercent==71)
 assert(settings.supportsDuoAutomatic(for:game))
 assert(!settings.supportsDuoAutomatic(for:TLApp(label:"Other game",packageName:nil,report:FakeReport(nativeEngine:.ue4))))
 var manual=settings;manual.automaticDuoProfile=false;manual.a20EfficiencyWorkers=false
 let roundtrip=try JSONDecoder().decode(TLAppSettings.self,from:JSONEncoder().encode(manual))
 assert(!roundtrip.automaticDuoProfile && !roundtrip.a20EfficiencyWorkers && roundtrip.customResolutionPercent==71 && !roundtrip.spatialUpscaling)
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
  cls.exe=p/'test';subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(ROOT/'src/app/Husk/HuskExecutionOptions.swift'),str(ROOT/'src/app/Husk/DuoDisplayPolicy.swift'),str(p/'Facades.swift'),str(p/'Settings.swift'),str(p/'main.swift'),str(p/'graphics.o'),'-o',str(cls.exe)],check=True)
 def case(self,name):subprocess.run([str(self.exe),name],check=True)
 def test_two_stage_geometry_uses_physical_panel_and_is_orientation_independent(self):self.case('geometry')
 def test_a20_runtime_match_fallback_and_independent_worker_opt_out(self):self.case('a20')
 def test_outer_unknown_nonphone_and_invalid_metrics_stay_out(self):self.case('guards')
 def test_opt_out_window_and_other_game_do_not_apply_profile(self):self.case('admission')
 def test_old_settings_migrate_without_overwriting_manual_values_and_opt_out_roundtrips(self):self.case('decode')
 def test_duo_phone_budget_survives_tablet_ui_idiom_and_manual_native_uses_panel_pixels(self):self.case('duo-settings')
 def test_m4_baseline_and_default_scaler_are_unchanged(self):self.case('m4')
if __name__=='__main__':unittest.main()
