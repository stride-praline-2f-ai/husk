#!/usr/bin/env python3
"""Protect existing per-game controls while keeping optional diagnostics organised."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = (ROOT / "src/app/Husk/TLAppSettings.swift").read_text()
APP = (ROOT / "src/app/Husk/SettingsTab.swift").read_text()

class SettingsGroupingTests(unittest.TestCase):
    def test_every_existing_unreal_control_is_present(self):
        # Prefer identity of the setting binding over UI label text, so renaming
        # labels won't silently delete an experimental control.
        names = [
            "unrealGraphics", "efficientResolution",
            "efficientFrameRate", "workerScheduling", "vulkanSubmission",
            "execution.prefill", "execution.commandBufferLimit",
            "execution.swapchainImages", "execution.initializationParking",
            "spatialUpscaling", "spatialInputPercent", "engineOnlyLimiter",
            "nativePipelineArchiveMode", "nativeArchiveVerification",
            "feedbackClockCorrection", "clockPresentation",
            "pipelineIdentification", "pipelineFeedback", "renderTargetInventory",
            "driverPhaseProfiling",
        ]
        for name in names:
            with self.subTest(setting=name):
                self.assertIn(f"$settings.{name}", GAME)
        # The 1%-step slider deliberately uses a clamped custom Binding rather
        # than a direct $settings binding. Assert both read and write paths.
        self.assertIn("Double(settings.customResolutionPercent)", GAME)
        self.assertIn("settings.customResolutionPercent = Int($0.rounded())", GAME)

    def test_simple_page_and_advanced_page_are_separate(self):
        self.assertIn("TLGameAdvancedSettingsView(settings: $settings, appID: app.id, automaticDuoActive: settings.duoAutomaticActive(for: app))", GAME)
        simple, advanced = GAME.split("private struct TLGameAdvancedSettingsView: View", 1)
        self.assertIn('Text("Game Graphics")', simple)
        self.assertIn('Text("Upscaling & Rendering")', advanced)
        self.assertIn('Text("Frame Pacing & CPU")', advanced)
        self.assertIn('Text("Vulkan & GPU Queues")', advanced)
        self.assertIn('Text("Pipeline Cache & Diagnostics")', advanced)
        self.assertIn('Text("General Game Diagnostics")', advanced)
        self.assertIn('.onChange(of: settings) { $0.save(appID) }', advanced)
        self.assertIn("EfficiencyDiagnosticsView()", advanced)
        self.assertIn("EfficiencyMetricKitView()", advanced)
        self.assertIn("EfficiencyProfilesView(settings: $settings", simple)

    def test_dungeons_single_routes_and_offline_controller_editor(self):
        dungeons = GAME.split("    private var dungeonsSettings: some View {", 1)[1].split("    private var allSettings: some View {", 1)[0]
        self.assertEqual(dungeons.count('Picker("Frame rate"'), 1)
        self.assertEqual(dungeons.count('Picker("Resolution"'), 1)
        self.assertNotIn('Picker("Frame Limit"', dungeons)
        self.assertNotIn('NavigationLink("Diagnostics") { dungeonsDiagnostics }', dungeons)
        self.assertIn("Game diagnostics run automatically.", dungeons)
        self.assertIn('dungeons: true', dungeons)
        self.assertIn('connectToGame: false', GAME)
        bar = (ROOT / 'src/app/Husk/TLUnityView.swift').read_text().split('private var barControls: some View', 1)[1].split('private var logPanel:', 1)[0]
        self.assertIn('engine == .ue4 && !settings.isDungeons(app)', bar)
        self.assertIn('settings.padShown && !settings.isDungeons(app)', bar)
        self.assertIn('Button { dismiss() }', bar)
        self.assertIn('Button { toggleInterface() }', bar)

    def test_native_apple_spatial_presets_and_retired_paths(self):
        launch = (ROOT / "src/app/Husk/TLUnityView.swift").read_text()
        native = (ROOT / "src/translation-layer-next/HuskNativeMetalFX.m").read_text()
        policy = (ROOT / "src/app/Husk/DuoDisplayPolicy.swift").read_text()
        self.assertIn("var duoSpatialPreset = DuoDisplayPolicy.inputPercent", GAME)
        self.assertIn("static let inputPercent = 60", policy)
        for value in (50,60,67,80):
            self.assertIn(f"tag({value})", GAME)
        self.assertIn("duoAutomaticActive(for: app) ? settings.duoSpatialPreset : settings.spatialInputPercent", launch)
        self.assertIn("spatialUpscaling = true", launch)
        self.assertIn("husk_ue4_set_frame_generation(false)", launch)
        self.assertNotIn("husk_metal4_preflight()", launch)
        self.assertNotIn("let metal4 = fw +", launch)
        self.assertIn("MTLFXFrameInterpolatorDescriptor", native)
        self.assertIn("!i->previous_color || !i->current_color || !i->depth || !i->motion", native)

    def test_dungeons_jit_wait_parking_defaults_and_manual_opt_out(self):
        launch = (ROOT / "src/app/Husk/TLUnityView.swift").read_text()
        c = (ROOT / "src/translation-layer-next/husk-tl-bionic-pthread.c").read_text()
        parking = (ROOT / "src/translation-layer-next/husk-tl-publication-wait.c").read_text()
        self.assertIn("var dungeonsJITLowPowerWait = true", GAME)
        self.assertIn("func effectiveExecution(for app: TLApp)", GAME)
        self.assertIn("if isDungeons(app) { selected.initializationParking = dungeonsJITLowPowerWait }", GAME)
        self.assertIn("Toggle(\"Park idle native JIT waits\", isOn: $settings.dungeonsJITLowPowerWait)", GAME)
        self.assertIn("execution: settings.effectiveExecution(for: app)", launch)
        self.assertIn("let keepJITLowPowerWait = execution.initializationParking", launch)
        self.assertIn("execution.initializationParking = keepJITLowPowerWait", launch)
        self.assertIn("husk_ue4_set_initialization_parking(execution.initializationParking)", launch)
        self.assertIn("tl_publication_wait(o,object_initializing)", c)
        self.assertIn("tl_publication_wait(once,once_initializing)", c)
        self.assertIn("pthread_cond_wait(&buckets[i].condition,&buckets[i].mutex)", parking)

    def test_gpu_private_native_metalfx_retains_one_prepared_scaler_per_image(self):
        native = (ROOT / "patches/metalfx/HuskSpatial.inc").read_text()
        self.assertIn("desc.storageMode=MTLStorageModePrivate", native)
        self.assertIn("huskSpatialPrepareImage(state,c,format)", native)
        self.assertIn("scaler.colorTexture=input;scaler.inputContentWidth=c.input_width", native)
        self.assertIn("if(output!=state->boundOutput)", native)
        self.assertIn("[scaler encodeToCommandBuffer:command]", native)
        self.assertIn("std::lock_guard<std::mutex> guard(state->lock)", native)
        self.assertIn("MTLFXSpatialScalerColorProcessingModeLinear", native)
        self.assertIn("MTLFXSpatialScalerColorProcessingModePerceptual", native)
        self.assertNotIn("newTextureWithDescriptor", native[native.index('bool huskSpatialEncode('):])

    def test_dungeons_native_metalfx_preflight_remains_opt_in_under_automatic_duo(self):
        launch = (ROOT / "src/app/Husk/TLUnityView.swift").read_text()
        report = (ROOT / "src/app/Husk/EfficiencyDiagnostics.swift").read_text()
        inventory = (ROOT / "src/translation-layer-next/husk-tl-render-inventory.c").read_text()
        # Automatic profile must preserve the requested opt-in image inventory
        # while still resetting the expensive unrelated profiling experiments.
        block = launch.split("private func applyDuoAutomaticProfile()",1)[1].split("private func launch(",1)[0]
        self.assertNotIn("renderTargetInventory = false", block)
        self.assertIn("driverProfiling = false; pipelineIdentification = false; pipelineFeedback = false", block)
        diag = GAME.split("private var dungeonsDiagnostics: some View",1)[1].split("private var dungeonsDetails:",1)[0]
        self.assertIn('Toggle("Render-target inventory", isOn: $settings.renderTargetInventory)',diag)
        self.assertNotIn('\n            }.disabled(settings.duoAutomaticActive(for: app))',diag)
        self.assertIn('Toggle("Driver phase profiling", isOn: $settings.driverPhaseProfiling)\n                    .disabled(settings.duoAutomaticActive(for: app))',diag)
        self.assertIn("tl_ri_metalfx_snapshot(&candidate)", report)
        self.assertIn("husk_native_metalfx_supported()", report)
        self.assertIn("HuskNativeMetalFX.h", (ROOT / "src/app/Husk/HuskBridge.h").read_text())
        self.assertIn('"native_metalfx_frame_interpolation_preflight": framegenProbe', report)
        for k in ("native_metalfx_interpolation_admitted", "semantic_depth_motion_verified",
                  "gpu_producer_consumer_sync_verified", "presenter_integrated"):
            self.assertIn(f'"{k}": false',report)
        self.assertIn("if(!atomic_load_explicit(&active,memory_order_relaxed)||!raw)return;",inventory)
        self.assertIn("tl_ri_metalfx_snapshot(tl_ri_metalfx_candidates *out)",inventory)

    def test_dungeons_game_log_is_unified_and_default_on_without_per_frame_tracing(self):
        launch = (ROOT / "src/app/Husk/TLUnityView.swift").read_text()
        native = (ROOT / "src/translation-layer-next/husk-tl-render-inventory.c").read_text()
        vk = (ROOT / "src/translation-layer-next/husk-tl-vulkan.m").read_text()
        self.assertIn('autoDungeonsLog: settings.isDungeons(app)', launch)
        self.assertIn('let inventoryMode: UInt32 = renderTargetInventory ? 2 : (autoDungeonsLog ? 1 : 0)', launch)
        self.assertIn('husk_ue4_set_render_inventory_mode(inventoryMode)', launch)
        self.assertIn('if autoDungeonsLog { tl_ri_activate("Dungeons") }', launch)
        self.assertIn('else { tl_ri_activate(nil) }', launch)
        self.assertIn('tl_em_process_sample(true, &process)',launch)
        self.assertIn('logDungeonsHealth(Double(p.fps))',launch)
        self.assertIn('guard now - lastDiagnosticsLogAt >= 15 else { return }', launch)
        self.assertIn('tl_ri_metalfx_snapshot(&candidate)',launch)
        self.assertIn('tl_vk_spatial_snapshot(&spatial)',launch)
        self.assertIn('husk_native_metalfx_supported()',launch)
        self.assertIn('private var showLog: Bool { get { showLogSetting && (settings.isDungeons(app) || devInfo)',launch)
        self.assertIn('HuskLog.recentLines(1200).joined(separator: "\\n")',launch)
        self.assertIn('Text(settings.isDungeons(app) ? "GAME LOG & DIAGNOSTICS" : "ATTEMPT LOG")',launch)
        self.assertIn('String(contentsOf: HuskLog.logFileURL, encoding: .utf8)',launch)
        self.assertIn('tl_ri_inventory_mode()<2', native)
        self.assertIn('!tl_ri_area_active()',vk)
        self.assertNotIn('husk_native_metalfx_encode(',launch)
        self.assertNotIn('tl_gput_native_start(true)',launch)

    def test_general_diagnostics_grouped_outside_about(self):
        self.assertIn('row(HuskDiagnosticsSettings()', APP)
        general = APP.split("struct HuskDiagnosticsSettings: View", 1)[1].split("struct AboutSettings: View", 1)[0]
        for name in ("Open Console", "Developer Info", "Device Checks", "Mass Test",
                     "Delayed OS Reports (MetricKit)", "Crash Reports"):
            with self.subTest(tool=name):
                self.assertIn(name, general)
        about = APP.split("struct AboutSettings: View", 1)[1]
        self.assertNotIn("Button { showLogs", about)
        self.assertNotIn("Toggle(isOn: $devInfo)", about)

if __name__ == "__main__":
    unittest.main()
