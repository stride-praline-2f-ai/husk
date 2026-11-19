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
        self.assertIn('NavigationLink("Diagnostics") { dungeonsDiagnostics }', dungeons)
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
