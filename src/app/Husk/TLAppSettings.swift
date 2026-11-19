// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// What a person can change about how one game runs here, kept in the game's own folder (`settings.json`) so it goes when the game
/// does. Like LiveContainer's per-app settings: each game has its own, and nothing here touches another game.
struct TLAppSettings: Codable, Equatable {
    /// Which way up the screen is while the game runs.
    enum Orientation: String, Codable, CaseIterable, Identifiable {
        /// What the game asks for (its manifest), landscape when it does not say.
        case auto, landscape, portrait
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .landscape: return "Landscape"
            case .portrait: return "Portrait"
            }
        }
    }

    /// How many pixels the game draws for each point of the screen. Fewer pixels run faster and take less memory.
    enum Resolution: String, Codable, CaseIterable, Identifiable {
        case low, medium, high, native
        var id: String { rawValue }
        var title: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .native: return "Native"
            }
        }
        var detail: String {
            switch self {
            case .low: return "1 pixel per point. Fastest."
            case .medium: return "1.5 pixels per point."
            case .high: return "2 pixels per point. The default."
            case .native: return "Every pixel the screen has. Sharpest, and heaviest."
            }
        }
        @MainActor var scale: CGFloat {
            switch self {
            case .low: return 1
            case .medium: return 1.5
            case .high: return 2
            case .native: return UIScreen.main.scale
            }
        }
    }

    /// When the on-screen controller is offered.
    enum PadMode: String, Codable, CaseIterable, Identifiable {
        /// For the games that cannot be played without a controller (Unreal, PC games through DXVK), when none is connected.
        case auto, always, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Automatic"
            case .always: return "Always"
            case .never: return "Never"
            }
        }
    }

    /// Where the app opens: full screen, or a window over Husk that can be moved, resized and minimised (Multitasking).
    enum WindowMode: String, Codable, CaseIterable, Identifiable {
        /// As Settings › Multitasking says for every app.
        case auto, window, fullScreen
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Default"
            case .window: return "Window"
            case .fullScreen: return "Full Screen"
            }
        }
    }

    enum UnrealGraphics: String, Codable, CaseIterable, Identifiable {
        case automatic, gameDefault, sharpHigh, efficientHigh
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .gameDefault: return "Game Default"
            case .sharpHigh: return "Sharp / High Quality"
            case .efficientHigh: return "Sharp / Efficient"
            }
        }
    }

    var unrealGraphics: UnrealGraphics = .automatic

    func isDungeons(_ app: TLApp) -> Bool {
        guard app.report?.nativeEngine == .ue4 else { return false }
        let package = app.packageName?.lowercased() ?? "", label = app.label.lowercased()
        return package == "com.nintendosss.spice" || package.contains("dungeons")
            || (label.contains("minecraft") && label.contains("dungeons"))
    }

    func usesSharpGraphics(for app: TLApp) -> Bool {
        guard app.report?.nativeEngine == .ue4 else { return false }
        switch unrealGraphics {
        case .gameDefault: return false
        case .sharpHigh, .efficientHigh: return true
        case .automatic:
            return isDungeons(app)
        }
    }

    enum WorkerScheduling: Int, Codable, CaseIterable, Identifiable {
        case gameDefault = 0, observe = 1, balanced = 2, adaptive = 3, relativeTrial = 4
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .gameDefault: return "Game Default"
            case .observe: return "Observe Only"
            case .balanced: return "Balanced (Experimental)"
            case .adaptive: return "Adaptive Trial (Experimental)"
            case .relativeTrial: return "Baseline-Relative Trial (Experimental)"
            }
        }
    }
    enum VulkanSubmission: Int, Codable, CaseIterable, Identifiable {
        case driverDefault = 0, asynchronous = 1
        var id: Int { rawValue }
        var title: String { self == .driverDefault ? "Driver Default" : "Async (Experimental)" }
    }
    var vulkanSubmission: VulkanSubmission = .driverDefault
    var engineOnlyLimiter = false
    var clockPresentation = false
    var feedbackClockCorrection = false
    var nativePipelineArchiveMode = 0
    var nativeArchiveVerification = false
    var execution = HuskExecutionOptions()
    // Dungeons' ARM64 library initialization can wait on translated bionic
    // pthread_once/lazy objects. Park competing threads instead of running
    // repeated sched_yield loops; changing this never lowers the FPS cap.
    var dungeonsJITLowPowerWait = true
    var pipelineIdentification = false
    var pipelineFeedback = false
    var automaticDuoProfile = true
    var a20EfficiencyWorkers = true
    // Old saved Metal 4 and Husk optical-flow fields remain decodable solely
    // for migration. They are never selected or run by the Apple-only route.
    var frameGeneration = false
    var metal4Renderer = false
    var enhancedMetal4 = false
    // User preference: request Apple's actual MetalFX interpolator when the
    // game supplies colour/depth/motion and an ordered Metal command buffer.
    var nativeAppleFrameInterpolation = true
    mutating func selectMetal4(_ enabled: Bool, bridgeAvailable: Bool = false) {
        metal4Renderer = false; enhancedMetal4 = false; frameGeneration = false
    }
    mutating func selectFrameGeneration(_ enabled: Bool, bridgeAvailable: Bool = false) {
        frameGeneration = false
    }
    mutating func selectEnhancedMetal4(_ enabled: Bool, bridgeAvailable: Bool = false) {
        metal4Renderer = false; enhancedMetal4 = false; frameGeneration = false
    }
    // DUNGEONS_SIMPLE_POLICY_BEGIN
    func dungeonsFrameChoice(automaticActive: Bool) -> Int {
        automaticActive ? 60 : efficientFrameRate.rawValue
    }
    mutating func selectDungeonsFrameChoice(_ value: Int, bridgeAvailable: Bool) {
        // 120 was Husk's retired colour-flow mode, not Apple MetalFX.
        frameGeneration = false
        if value == 30 { efficientFrameRate = .cool; automaticDuoProfile = false }
        if value == 60 { efficientFrameRate = .smooth }
    }
    var dungeonsResolutionChoice: Int {
        efficientResolution == .automatic ? 0 : (efficientResolution == .native ? 100 : -1)
    }
    var dungeonsResolutionPercent: Int {
        efficientResolution == .custom ? customResolutionPercent : (efficientResolution.rawValue > 0 ? efficientResolution.rawValue : customResolutionPercent)
    }
    mutating func selectDungeonsResolutionChoice(_ value: Int) {
        if value == 0 {
            efficientResolution = .automatic
            // Automatic resolution must not silently replace a chosen30FPS cap.
            automaticDuoProfile = frameGeneration || efficientFrameRate == .smooth
        } else {
            let percent = dungeonsResolutionPercent
            efficientResolution = value == 100 ? .native : .custom
            if value != 100 { customResolutionPercent = percent }
            automaticDuoProfile = false
        }
    }
    var dungeonsRendererChoice: Int { 2 }
    mutating func selectDungeonsRendererChoice(_ value: Int, bridgeAvailable: Bool) {
        selectMetal4(false)
    }
    // DUNGEONS_SIMPLE_POLICY_END
    var sharedMemoryReserve = true
    var spatialUpscaling = false
    var spatialInputPercent = 80
    // Independent Duo preset: preserves other device/manual upscaling choices.
    var duoSpatialPreset = DuoDisplayPolicy.inputPercent
    var renderTargetInventory = false
    var driverPhaseProfiling = false
    var workerScheduling: WorkerScheduling = .balanced

    enum EfficientFrameRate: Int, Codable, CaseIterable, Identifiable {
        case cool = 30, smooth = 60
        var id: Int { rawValue }
        var title: String { self == .cool ? "30 FPS · Lower Power" : "60 FPS · Smoother" }
    }
    var efficientFrameRate: EfficientFrameRate = .smooth

    enum EfficientResolution: Int, Codable, CaseIterable, Identifiable {
        case custom = -1, automatic = 0, native = 100, ultra = 95, verySharp = 90, sharp = 85, quality = 80, balanced = 75, economical = 70, performance = 65
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .custom: return "Custom · 1% Steps"
            case .automatic: return "Automatic · Reduced Resolution"
            case .native: return "Native · 100%"
            case .ultra: return "95% · Compare with Native"
            case .verySharp: return "90%"
            case .quality: return "80%"
            case .economical: return "70%"
            case .sharp: return "Sharp · 85%"
            case .balanced: return "Balanced · 75%"
            case .performance: return "Performance · 65%"
            }
        }
    }
    var efficientResolution: EfficientResolution = .automatic
    var customResolutionPercent = 80

    func usesEfficientGraphics(for app: TLApp) -> Bool {
        usesSharpGraphics(for: app) && (unrealGraphics == .automatic || unrealGraphics == .efficientHigh)
    }

    func effectiveExecution(for app: TLApp) -> HuskExecutionOptions {
        var selected = execution.safe
        if isDungeons(app) { selected.initializationParking = dungeonsJITLowPowerWait }
        return selected
    }

    func supportsDuoAutomatic(for app: TLApp) -> Bool {
        automaticDuoProfile && usesEfficientGraphics(for: app) && isDungeons(app)
    }
    @MainActor func duoAutomaticActive(for app: TLApp) -> Bool {
        supportsDuoAutomatic(for: app) && window != .window && (window != .auto || !AppWindows.defaultWindowed)
            && DuoDisplayPolicy.metrics(screen: .main).isInner
    }

    @MainActor func renderScale(for app: TLApp) -> CGFloat {
        guard usesSharpGraphics(for: app) else { return resolution.scale }
        let screen = UIScreen.main
        guard usesEfficientGraphics(for: app) else { return screen.scale }
        let percent = efficientResolution == .custom ? customResolutionPercent : efficientResolution.rawValue
        let duo = DuoDisplayPolicy.metrics(screen: screen)
        if let scale = duo.scale(percent: duoAutomaticActive(for: app) ? 0 : percent) {
            return CGFloat(scale)
        }
        let fraction = tl_ue4_resolution_fraction(
            Int32((screen.bounds.width * screen.scale).rounded()),
            Int32((screen.bounds.height * screen.scale).rounded()),
            UIDevice.current.userInterfaceIdiom == .pad, Int32(efficientResolution == .custom ? customResolutionPercent : efficientResolution.rawValue))
        return screen.scale * CGFloat(fraction)
    }

    @MainActor func fullscreenSpatialInputEstimate(for app: TLApp) -> String {
        let size = UIScreen.main.bounds.size
        let scale = renderScale(for: app)
        let width = Int((max(size.width, size.height) * scale).rounded()) & ~7
        let height = Int((min(size.width, size.height) * scale).rounded()) & ~7
        let percent = duoAutomaticActive(for: app) ? duoSpatialPreset : spatialInputPercent
        // Match the eight-pixel-aligned native Vulkan scaling contract.
        let inputWidth = ((width * percent + 400) / 800) * 8
        let inputHeight = ((height * percent + 400) / 800) * 8
        return "\(inputWidth) × \(inputHeight) → \(width) × \(height)"
    }

    @MainActor func fullscreenResolutionEstimate(for app: TLApp) -> String {
        let size = UIScreen.main.bounds.size
        let scale = renderScale(for: app)
        let width = Int((max(size.width, size.height) * scale).rounded()) & ~7
        let height = Int((min(size.width, size.height) * scale).rounded()) & ~7
        return "\(width) × \(height)"
    }

    var orientation: Orientation = .auto
    var window: WindowMode = .auto
    var resolution: Resolution = .high
    /// The frames-per-second readout in the top bar.
    var showStats = true
    /// Start with nothing over the picture: no bar, no controller, no readout. Three fingers tapped together bring them back.
    var cleanView = false
    /// Stop the screen from dimming and locking while the game is on.
    var keepAwake = true
    var pad: PadMode = .auto
    /// Whether the controller is showing right now (the Pad button in the top bar toggles it).
    var padShown = true
    var padOpacity = 1.0
    var haptics = true
    /// Geometry Dash only: load Geode, its mod loader (Geode.swift).
    var geode = false

    init() {}

    // Settings written by an older Husk lack the keys a newer one added; each falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customResolutionPercent = min(100, max(65, try c.decodeIfPresent(Int.self, forKey: .customResolutionPercent) ?? 80))
        efficientResolution = try c.decodeIfPresent(EfficientResolution.self, forKey: .efficientResolution) ?? .automatic
        vulkanSubmission = try c.decodeIfPresent(VulkanSubmission.self, forKey: .vulkanSubmission) ?? .driverDefault
        engineOnlyLimiter = try c.decodeIfPresent(Bool.self, forKey: .engineOnlyLimiter) ?? false
        clockPresentation = try c.decodeIfPresent(Bool.self, forKey: .clockPresentation) ?? false
        feedbackClockCorrection = try c.decodeIfPresent(Bool.self, forKey: .feedbackClockCorrection) ?? false
        execution = (try c.decodeIfPresent(HuskExecutionOptions.self, forKey: .execution) ?? .init()).safe
        dungeonsJITLowPowerWait = try c.decodeIfPresent(Bool.self, forKey: .dungeonsJITLowPowerWait) ?? true
        nativeArchiveVerification = try c.decodeIfPresent(Bool.self, forKey: .nativeArchiveVerification) ?? false
        let archiveMode = try c.decodeIfPresent(Int.self, forKey: .nativePipelineArchiveMode) ?? 0
        nativePipelineArchiveMode = [0,1,2].contains(archiveMode) ? archiveMode : 0
        pipelineIdentification = try c.decodeIfPresent(Bool.self, forKey: .pipelineIdentification) ?? false
        pipelineFeedback = try c.decodeIfPresent(Bool.self, forKey: .pipelineFeedback) ?? false
        automaticDuoProfile = try c.decodeIfPresent(Bool.self, forKey: .automaticDuoProfile) ?? true
        a20EfficiencyWorkers = try c.decodeIfPresent(Bool.self, forKey: .a20EfficiencyWorkers) ?? true
        // Ignore stale persisted renderer/old-FG flags, preserving app data.
        metal4Renderer = false
        enhancedMetal4 = false
        frameGeneration = false
        nativeAppleFrameInterpolation = try c.decodeIfPresent(Bool.self, forKey: .nativeAppleFrameInterpolation) ?? true
        sharedMemoryReserve = try c.decodeIfPresent(Bool.self, forKey: .sharedMemoryReserve) ?? true
        spatialUpscaling = try c.decodeIfPresent(Bool.self, forKey: .spatialUpscaling) ?? false
        let inputPercent = try c.decodeIfPresent(Int.self, forKey: .spatialInputPercent) ?? 80
        spatialInputPercent = [50,60,67,80,85,90,95].contains(inputPercent) ? inputPercent : 80
        let duoPercent = try c.decodeIfPresent(Int.self, forKey: .duoSpatialPreset) ?? DuoDisplayPolicy.inputPercent
        duoSpatialPreset = [50,60,67,80].contains(duoPercent) ? duoPercent : DuoDisplayPolicy.inputPercent
        renderTargetInventory = try c.decodeIfPresent(Bool.self, forKey: .renderTargetInventory) ?? false
        driverPhaseProfiling = try c.decodeIfPresent(Bool.self, forKey: .driverPhaseProfiling) ?? false
        workerScheduling = try c.decodeIfPresent(WorkerScheduling.self, forKey: .workerScheduling) ?? .balanced
        efficientFrameRate = try c.decodeIfPresent(EfficientFrameRate.self, forKey: .efficientFrameRate) ?? .smooth
        unrealGraphics = try c.decodeIfPresent(UnrealGraphics.self, forKey: .unrealGraphics) ?? .automatic
        orientation = try c.decodeIfPresent(Orientation.self, forKey: .orientation) ?? .auto
        resolution = try c.decodeIfPresent(Resolution.self, forKey: .resolution) ?? .high
        showStats = try c.decodeIfPresent(Bool.self, forKey: .showStats) ?? true
        cleanView = try c.decodeIfPresent(Bool.self, forKey: .cleanView) ?? false
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        pad = try c.decodeIfPresent(PadMode.self, forKey: .pad) ?? .auto
        padShown = try c.decodeIfPresent(Bool.self, forKey: .padShown) ?? true
        padOpacity = try c.decodeIfPresent(Double.self, forKey: .padOpacity) ?? 1.0
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        geode = try c.decodeIfPresent(Bool.self, forKey: .geode) ?? false
        window = try c.decodeIfPresent(WindowMode.self, forKey: .window) ?? .auto
    }

    private static func url(_ id: String) -> URL {
        TranslationLayer.root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("settings.json")
    }

    static func load(_ id: String) -> TLAppSettings {
        (try? Data(contentsOf: url(id))).flatMap { try? JSONDecoder().decode(TLAppSettings.self, from: $0) } ?? TLAppSettings()
    }

    func save(_ id: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // The folder is gone when the app was removed while its settings page was open.
        guard FileManager.default.fileExists(atPath: Self.url(id).deletingLastPathComponent().path),
              let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.url(id), options: .atomic)
    }
}

// MARK: - The settings page

/// One game's settings, opened from its page or from its tile's menu.
struct TLAppSettingsView: View {
    let app: TLApp
    private let advancedOnly: Bool

    @State private var profilesSheet = false
    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var geode = GeodeSupport.shared
    @State private var settings: TLAppSettings
    @State private var name: String
    @State private var dataSize: String = "…"
    @State private var confirmReset = false
    @State private var frameEvidenceMessage = ""
    @State private var frameEvidenceBusy = false
    @State private var frameEvidenceFiles: [URL] = []
    @State private var showFrameEvidenceShare = false
    @FocusState private var nameFocused: Bool

    init(app: TLApp, advancedOnly: Bool = false) {
        self.app = app
        self.advancedOnly = advancedOnly
        _settings = State(initialValue: TLAppSettings.load(app.id))
        _name = State(initialValue: app.label)
    }

    /// The game is loaded in this run of Husk, so what it keeps cannot be swapped from under it.
    private var inUse: Bool {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), let apk = app.apks.first else { return false }
        return loaded == apk
    }

    private var dataDirs: [URL] {
        let dir = TranslationLayer.root.appendingPathComponent(app.id, isDirectory: true)
        return ["unity-data", "cocos-data", "minecraft-data", "sdl-data", "ue4-data", "gta-data", "na-data", "godot-data", "flutter-data", "gm-data", "web"]
            .map { dir.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var isDungeons: Bool { settings.isDungeons(app) }

    var body: some View {
        Group {
            if isDungeons {
                if advancedOnly { dungeonsAdvancedSettings } else { dungeonsSettings }
            } else { allSettings }
        }
        .huskForm()
        .navigationTitle(isDungeons && advancedOnly ? "Advanced Settings" : "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings) { $0.save(app.id) }
        .onChange(of: settings.geode) { on in
            if on { Task { await geode.prepare(app) } } else { geode.remove(app) }
        }
        .onChange(of: nameFocused) { focused in if !focused { rename() } }
        .onDisappear { rename() }
        .onAppear { if isDungeons && !advancedOnly { settings = TLAppSettings.load(app.id) } }
        .task { dataSize = await Self.measure(dataDirs) }
        .sheet(isPresented: $showFrameEvidenceShare) { ShareSheet(items: frameEvidenceFiles.map { $0 as Any }) }
        .confirmationDialog("Reset the data of \(app.label)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Game Data", role: .destructive) {
                for dir in dataDirs { try? FileManager.default.removeItem(at: dir) }
                HuskLog.log("tl", "reset the data of \(app.label)")
                Task { dataSize = await Self.measure(dataDirs) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves, settings and caches the game made here are deleted.")
        }
    }

    private var dungeonsSettings: some View {
        HuskForm {
            Section {
                Picker("Graphics", selection: Binding(get: {
                    settings.usesEfficientGraphics(for: app) ? TLAppSettings.UnrealGraphics.automatic : settings.unrealGraphics
                }, set: {
                    settings.unrealGraphics = $0
                    if !settings.usesEfficientGraphics(for: app) { settings.selectFrameGeneration(false) }
                })) {
                    Text("Recommended").tag(TLAppSettings.UnrealGraphics.automatic)
                    Text("Native high quality").tag(TLAppSettings.UnrealGraphics.sharpHigh)
                    Text("Game default").tag(TLAppSettings.UnrealGraphics.gameDefault)
                }
                Picker("Frame rate", selection: Binding(get: {
                    settings.dungeonsFrameChoice(automaticActive: settings.duoAutomaticActive(for: app))
                }, set: { settings.selectDungeonsFrameChoice($0, bridgeAvailable: Metal4DriverCapabilities.current.frameGeneration) })) {
                    Text("60 FPS").tag(60)
                    Text("30 FPS").tag(30)
                }.disabled(!settings.usesEfficientGraphics(for: app))
                Picker("Resolution", selection: Binding(get: { settings.duoAutomaticActive(for: app) ? 0 : settings.dungeonsResolutionChoice }, set: { settings.selectDungeonsResolutionChoice($0) })) {
                    Text("Automatic").tag(0)
                    Text("Native").tag(100)
                    Text("Custom").tag(-1)
                }.disabled(!settings.usesEfficientGraphics(for: app))
                if settings.dungeonsResolutionChoice == -1 && !settings.duoAutomaticActive(for: app) {
                    HStack {
                        Slider(value: Binding(get: { Double(settings.dungeonsResolutionPercent) }, set: {
                            settings.customResolutionPercent = Int($0.rounded()); settings.efficientResolution = .custom; settings.automaticDuoProfile = false
                        }), in: 65...100, step: 1)
                        Text("\(settings.dungeonsResolutionPercent)%").monospacedDigit()
                    }.disabled(!settings.usesEfficientGraphics(for: app))
                }
                LabeledContent("Output estimate", value: settings.fullscreenResolutionEstimate(for: app))
                if settings.duoAutomaticActive(for: app) {
                    LabeledContent("Apple MetalFX input → output", value: settings.fullscreenSpatialInputEstimate(for: app))
                }
                LabeledContent("Renderer", value: "Vulkan → Apple Metal (MoltenVK)")
                LabeledContent("Apple frame interpolation", value: "Awaiting engine motion/depth bridge")
            } header: { Text(app.label) } footer: {
                Text("Original Husk frame generation has been retired. Native Apple interpolation will not run until real scene motion/depth buffers are available. Until then, gameplay uses real rendered frames.")
            }
            Section {
                NavigationLink("Controls & display") { dungeonsControls }
                NavigationLink("Advanced") { dungeonsAdvancedSettings }
                NavigationLink("Diagnostics") { dungeonsDiagnostics }
                NavigationLink("App details & storage") { dungeonsDetails }
            }
        }
    }

    private var dungeonsControls: some View {
        HuskForm {
            Section("Controller") {
                Picker("On-screen controller", selection: $settings.pad) {
                    ForEach(TLAppSettings.PadMode.allCases) { Text($0.title).tag($0) }
                }
                if settings.pad != .never {
                    Slider(value: $settings.padOpacity, in: 0.3...1) { Text("Controller opacity") }
                    Toggle("Vibrate on a press", isOn: $settings.haptics)
                    NavigationLink("Edit controller layout") { DungeonsPadLayoutEditor(appID: app.id) }
                        .disabled(inUse)
                }
            }
            Section("Display") {
                if !settings.usesSharpGraphics(for: app) {
                    Picker("Game-default resolution", selection: $settings.resolution) {
                        ForEach(TLAppSettings.Resolution.allCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Orientation", selection: $settings.orientation) {
                    ForEach(TLAppSettings.Orientation.allCases) { Text($0.title).tag($0) }
                }
                Picker("Open in", selection: $settings.window) {
                    ForEach(TLAppSettings.WindowMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Performance readout", isOn: $settings.showStats)
                Toggle("Start with interface hidden", isOn: $settings.cleanView)
                Toggle("Keep the screen on", isOn: $settings.keepAwake)
            }
            Section {
                Text("Three fingers show or hide the Husk bar. The bar keeps Close and controller visibility; settings and diagnostics live here. Edit the layout before loading the game. Display changes require a full restart.")
            }
        }.navigationTitle("Controls & Display")
    }

    private var dungeonsAdvancedSettings: some View {
        HuskForm {
            Section {
                if settings.duoAutomaticActive(for: app) {
                    Picker("Duo MetalFX preset", selection: $settings.duoSpatialPreset) {
                        Text("Balanced · 60% · 60 FPS target").tag(60)
                        Text("Max battery · 50% · 60 FPS target").tag(50)
                        Text("Quality · 67% · 60 FPS target").tag(67)
                        Text("Extra sharp · 80% · 60 FPS target").tag(80)
                    }
                    LabeledContent("Render → output", value: settings.fullscreenSpatialInputEstimate(for: app))
                    Text("Apple MetalFX spatial scaling is enabled by automatic device tuning. FPS is real game rendering, not generated frames.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Toggle("Apple MetalFX spatial upscaling", isOn: $settings.spatialUpscaling)
                    if settings.spatialUpscaling {
                        Picker("Input scale", selection: $settings.spatialInputPercent) {
                            ForEach([50,60,67,80,85,90,95], id: \.self) { Text("\($0)% of output dimensions").tag($0) }
                        }
                    }
                }
                Toggle("Prefer native Apple frame interpolation", isOn: $settings.nativeAppleFrameInterpolation)
                Text("Requires genuine Unreal Engine depth, motion vectors and scene colour. Requested by default, but inactive until the engine bridge is available. No image-derived substitutes.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Native pipeline cache", selection: Binding(get: { settings.nativePipelineArchiveMode == 2 }, set: { settings.nativePipelineArchiveMode = $0 ? 2 : 0 })) {
                    Text("Off").tag(false); Text("On").tag(true)
                }
                Toggle("Shared game memory", isOn: $settings.sharedMemoryReserve)
                Toggle("Park idle native JIT waits", isOn: $settings.dungeonsJITLowPowerWait)
                Text("Uses native condition-variable sleeps instead of CPU-spinning during contested Unreal library/object initialization. Does not change executable memory, graphics, or the 60 FPS target. Disable and restart if startup or gameplay regresses.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Graphics & Memory") } footer: {
                Text("MetalFX's spatial pass scales the whole rendered image, including any in-game HUD, so text clarity is not guaranteed at 50%. Native frame interpolation remains unavailable without genuine engine motion/depth. Switching resolutions or folding requires swapchain recreation; restart the game when changing presets.")
            }
            Section {
                if DuoDisplayPolicy.metrics(screen: .main).isInner {
                    Toggle("Automatic device tuning", isOn: $settings.automaticDuoProfile)
                    if DuoDisplayPolicy.supportsA20Workers {
                        Toggle("A20 efficiency workers", isOn: $settings.a20EfficiencyWorkers)
                            .disabled(!settings.duoAutomaticActive(for: app))
                    }
                }
                if settings.duoAutomaticActive(for: app) {
                    Text("Automatic workers, driver-default queues and native Apple MetalFX spatial scaling where supported. Legacy frame generation and Metal 4 are not used.")
                }
                Button("Saved graphics experiments") { profilesSheet = true }
                    .sheet(isPresented: $profilesSheet) { EfficiencyProfilesView(settings: $settings, game: app.packageName ?? app.label) }
                NavigationLink("Developer experiments") {
                    TLGameAdvancedSettingsView(settings: $settings, appID: app.id, automaticDuoActive: settings.duoAutomaticActive(for: app), dungeons: true)
                }
            } header: { Text("Device Tuning") } footer: {
                Text("Automatic tuning applies only to the supported inner display in full screen. Restart after changing these controls. No measured energy benefit is assumed.")
            }
        }.navigationTitle("Advanced")
    }

    private var dungeonsDiagnostics: some View {
        HuskForm {
            Section {
                Button("Capture frame-generation evidence") {
                    do { frameEvidenceMessage = try FramegenDiagnostics.arm(app: app, inUse: inUse) }
                    catch { frameEvidenceMessage = error.localizedDescription }
                }.disabled(!settings.frameGeneration || frameEvidenceBusy)
                Button("Capture status") { frameEvidenceMessage = FramegenDiagnostics.status }
                Button("Cancel capture") { FramegenDiagnostics.cancelPending(); frameEvidenceMessage = "Capture cancelled. Existing files are kept." }
                Button(frameEvidenceBusy ? "Preparing bundle…" : "Share diagnostic bundle") { exportFrameEvidence() }.disabled(frameEvidenceBusy)
                Text(frameEvidenceMessage.isEmpty ? FramegenDiagnostics.status : frameEvidenceMessage)
            } header: { Text("Image Quality") } footer: {
                Text("Capture is opt-in and local. It saves source images, reconstructed output, flow fields, quality decisions and timing. Export includes measured image differences; missing evidence stays unavailable. No recording or automatic upload.")
            }
            Section("Performance & Cache") {
                NavigationLink("Performance test & cache inspection") { EfficiencyDiagnosticsView() }
                NavigationLink("Delayed OS reports") { EfficiencyMetricKitView() }
            }
            Section {
                Toggle("Render-target inventory", isOn: $settings.renderTargetInventory)
                if settings.renderTargetInventory {
                    Text("Opt-in Vulkan image formats and sizes only. This can identify possible depth/motion-buffer candidates, not prove that they contain Unreal velocity or depth. Export the performance report after gameplay; restart to begin or stop collection.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Driver phase profiling", isOn: $settings.driverPhaseProfiling)
                    .disabled(settings.duoAutomaticActive(for: app))
                Picker("Pipeline detail", selection: Binding(get: { settings.pipelineIdentification ? (settings.pipelineFeedback ? 2 : 1) : 0 }, set: {
                    settings.pipelineIdentification = $0 > 0; settings.pipelineFeedback = $0 == 2
                })) {
                    Text("Off").tag(0); Text("Identification").tag(1); Text("Identification & feedback").tag(2)
                }.disabled(settings.duoAutomaticActive(for: app))
                Toggle("Verify native archive reuse", isOn: $settings.nativeArchiveVerification)
                    .disabled(settings.duoAutomaticActive(for: app) || settings.nativePipelineArchiveMode != 2 || (settings.metal4Renderer && !settings.enhancedMetal4))
            } header: { Text("Detailed Collection") } footer: {
                Text(settings.duoAutomaticActive(for: app)
                     ? "Render-target inventory is available as a one-shot diagnostic with Automatic Duo tuning. Other detailed launch collection remains overridden. Disable inventory and restart after exporting."
                     : "Detailed collection adds overhead and needs a full restart. Leave it off during normal play.")
            }
        }.navigationTitle("Diagnostics")
    }

    private var dungeonsDetails: some View {
        HuskForm {
            Section("App") {
                TextField("Name", text: $name).focused($nameFocused).onSubmit { rename() }
                Button("Add to Home Screen") { AppClip.generate(for: app) }
            }
            Section {
                LabeledContent("Saved by the game", value: dataSize)
                Button("Reset Game Data", role: .destructive) { confirmReset = true }.disabled(inUse || dataDirs.isEmpty)
            } header: { Text("Storage") } footer: {
                Text("Reset deletes saves, downloaded data and game caches. Graphics changes and profile changes never reset game data.")
            }
        }.navigationTitle("App Details")
    }

    private var allSettings: some View {
        HuskForm {
            Section {
                HStack(spacing: 14) {
                    AppIcon(path: app.iconPath, size: 52)
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { rename() }
                        .font(.system(size: 18, weight: .semibold))
                }
                .padding(.vertical, 2)
            } footer: {
                Text("What the game is called in Husk. The game itself is not changed.")
            }

            Section {
                Picker("Orientation", selection: $settings.orientation) {
                    ForEach(TLAppSettings.Orientation.allCases) { Text($0.title).tag($0) }
                }
                if settings.usesSharpGraphics(for: app) {
                    LabeledContent("Resolution", value: "See Game Graphics")
                } else {
                    Picker("Resolution", selection: $settings.resolution) {
                        ForEach(TLAppSettings.Resolution.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Performance readout", isOn: $settings.showStats)
                Toggle("Keep the screen on", isOn: $settings.keepAwake)
            } header: {
                Text("Display")
            } footer: {
                Text("\(settings.usesEfficientGraphics(for: app) ? "Use Game Graphics to choose the rendering resolution." : (settings.usesSharpGraphics(for: app) ? "The graphics preset uses Native resolution." : settings.resolution.detail)) Orientation and resolution apply the next time the game starts, and a game already "
                   + "running in this session needs Husk closed and opened again.")
            }

            if app.report?.nativeEngine == .ue4 {
                Section {
                    if isDungeons {
                        Picker("Graphics preset", selection: Binding(get: { settings.unrealGraphics }, set: {
                            settings.unrealGraphics = $0
                            if !settings.usesEfficientGraphics(for: app) { settings.selectFrameGeneration(false) }
                        })) {
                            ForEach(TLAppSettings.UnrealGraphics.allCases) { Text($0.title).tag($0) }
                        }
                    } else {
                    Picker("Graphics Preset", selection: $settings.unrealGraphics) {
                        ForEach(TLAppSettings.UnrealGraphics.allCases) { Text($0.title).tag($0) }
                    }
                    }
                    LabeledContent("Active Preset", value: settings.usesEfficientGraphics(for: app) ? "Sharp / Efficient" : (settings.usesSharpGraphics(for: app) ? "Sharp / High Quality" : "Game Default"))
                    Toggle("Shared Game Memory", isOn: $settings.sharedMemoryReserve)
                    Text("Borrows extra game memory on iPhone when supported. Keep app extensions when installing; an additional App ID may be needed. Restart required.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if settings.usesEfficientGraphics(for: app) {
                        if DuoDisplayPolicy.metrics(screen: .main).isInner {
                            Toggle("Automatic Duo Inner Screen", isOn: $settings.automaticDuoProfile)
                            if settings.duoAutomaticActive(for: app) {
                                if DuoDisplayPolicy.supportsA20Workers {
                                    Toggle("A20 Efficiency Workers", isOn: $settings.a20EfficiencyWorkers)
                                    Text("Uses the runtime performance-core count for the normal-priority worker allowance; extra eligible workers use lower priority only after stable gameplay. Turn off to restore Balanced without changing resolution or MetalFX. Restart required.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Text("Automatic native Apple MetalFX spatial scaling where available. No KosmicKrisp or Husk colour-flow frame generation. Native interpolation requires genuine game buffers.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if settings.duoAutomaticActive(for: app) {
                            LabeledContent("Rendering Resolution", value: "Automatic · Reduced Resolution")
                        } else {
                            Picker("Rendering Resolution", selection: $settings.efficientResolution) {
                                ForEach(TLAppSettings.EfficientResolution.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        if settings.efficientResolution == .custom && !settings.duoAutomaticActive(for: app) {
                            LabeledContent("Render Scale", value: "\(settings.customResolutionPercent)%")
                            Slider(value: Binding(get: { Double(settings.customResolutionPercent) },
                                                  set: { settings.customResolutionPercent = Int($0.rounded()) }),
                                   in: 65...100, step: 1)
                        }
                        LabeledContent("Fullscreen Target", value: settings.fullscreenResolutionEstimate(for: app))
                        if settings.duoAutomaticActive(for: app) {
                            LabeledContent("Frame Limit", value: "60 FPS · Smoother")
                        } else {
                            Picker("Frame Limit", selection: $settings.efficientFrameRate) {
                                ForEach(TLAppSettings.EfficientFrameRate.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }
                    Button("Device Graphics Profiles") { profilesSheet = true }
                        .sheet(isPresented: $profilesSheet) {
                            EfficiencyProfilesView(settings: $settings, game: app.packageName ?? app.label)
                        }
                } header: {
                    Text("Game Graphics")
                } footer: {
                    Text("Sharp / Efficient is automatic for Minecraft Dungeons. Resolution and FPS choices apply on the next launch. Fullscreen Target is an estimate, not a guarantee.")
                }

                Section {
                    NavigationLink {
                        TLGameAdvancedSettingsView(settings: $settings, appID: app.id, automaticDuoActive: settings.duoAutomaticActive(for: app))
                    } label: {
                        Label("Advanced Graphics & Diagnostics", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Optional performance experiments, their matching diagnostic controls and general game reports. Leave experimental options at their defaults unless testing one change at a time.")
                }
            }

            Section {
                Picker("Open In", selection: $settings.window) {
                    ForEach(TLAppSettings.WindowMode.allCases) { m in
                        Text(m == .auto ? "Default (\(AppWindows.defaultWindowed ? "Window" : "Full Screen"))" : m.title).tag(m)
                    }
                }
            } header: {
                Text("Multitasking")
            } footer: {
                Text("In a window, \(app.label) runs over Husk: move it by its title bar, resize it from the corner, and minimise it to "
                   + "the dock at the edge of the screen while you use the rest of Husk.")
            }

            Section {
                Toggle("Hide the interface", isOn: $settings.cleanView)
            } header: {
                Text("Screenshots")
            } footer: {
                Text("The game starts with nothing over it: no bar, no controller, no readout. Tap with three fingers at once to bring "
                   + "the bar back, and again to hide it. The Hide button in the bar does the same while playing.")
            }

            if app.packageName == GeodeSupport.gamePackage {
                Section {
                    Toggle("Geode", isOn: $settings.geode)
                    if settings.geode { geodeStatus }
                } header: {
                    Text("Mods")
                } footer: {
                    Text("Geode is the mod loader for Geometry Dash. With it on, Husk downloads Geode for this version of the "
                       + "game, and mods are found and installed in the game itself, from Geode's button on the main menu. "
                       + "Applies the next time the game starts.")
                }
            }

            Section {
                Picker("On-screen controller", selection: $settings.pad) {
                    ForEach(TLAppSettings.PadMode.allCases) { Text($0.title).tag($0) }
                }
                if settings.pad != .never {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Opacity")
                        Slider(value: $settings.padOpacity, in: 0.3...1)
                    }
                    Toggle("Vibrate on a press", isOn: $settings.haptics)
                }
            } header: {
                Text("Controller")
            } footer: {
                Text("Automatic offers the controller for games that cannot be played without one (Unreal Engine games), when no real "
                   + "controller is connected. Always offers it for any game that understands one. A paired controller is always used.")
            }

            Section {
                Button { AppClip.generate(for: app) } label: {
                    Label("Generate App Clip", systemImage: "apps.iphone.badge.plus")
                }
            } header: {
                Text("Home Screen")
            } footer: {
                Text("Puts \(app.label) on your Home Screen with its own icon. Tapping it opens Husk straight into the game. Husk "
                   + "downloads a profile: open Settings, tap Profile Downloaded, then Install.")
            }

            Section {
                DetailRow(label: "Saved by the game", value: dataSize, mono: false)
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset Game Data", systemImage: "arrow.counterclockwise")
                }
                .disabled(inUse || dataDirs.isEmpty)
            } header: {
                Text("Data")
            } footer: {
                Text(inUse ? "The game is loaded in this session. Close Husk completely and open it again to reset its data."
                           : "Deletes what the game saved and downloaded here: saves, settings and caches. The game itself stays.")
            }
        }
    }

    private func exportFrameEvidence() {
        do {
            let (capture, logs, context, output) = try FramegenDiagnostics.exportContext(appID: app.id)
            frameEvidenceBusy = true
            DispatchQueue.global(qos: .utility).async {
                do {
                    try FrameEvidenceFiles.bundle(capture: capture, logs: logs, context: context, output: output)
                    DispatchQueue.main.async {
                        frameEvidenceBusy = false; frameEvidenceFiles = [output]; showFrameEvidenceShare = true
                        frameEvidenceMessage = "Bundle ready. Missing or incomplete capture stages are listed inside."
                        FramegenDiagnostics.pruneExports(keeping: output)
                    }
                } catch {
                    let message = error.localizedDescription
                    DispatchQueue.main.async { frameEvidenceBusy = false; frameEvidenceMessage = "Export failed: " + message }
                }
            }
        } catch { frameEvidenceMessage = error.localizedDescription }
    }

    @ViewBuilder
    private var geodeStatus: some View {
        switch geode.current(app) {
        case .idle:
            Button("Download Geode") { Task { await geode.prepare(app) } }
        case .working(let what):
            HStack(spacing: 10) { ProgressView(); Text(what).foregroundStyle(.secondary) }
        case .ready(let version):
            LabeledContent("Geode", value: "v\(version), ready")
        case .failed(let why):
            VStack(alignment: .leading, spacing: 6) {
                Text(why).font(.footnote).foregroundStyle(.orange)
                Button("Try Again") { Task { await geode.prepare(app) } }
            }
        }
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != app.label else { return }
        store.rename(app, to: trimmed)
    }

    private static func measure(_ dirs: [URL]) async -> String {
        await Task.detached(priority: .utility) {
            var bytes: Int64 = 0
            for dir in dirs {
                let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
                while let url = walker?.nextObject() as? URL {
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if values?.isRegularFile == true { bytes += Int64(values?.fileSize ?? 0) }
                }
            }
            return bytes == 0 ? "nothing" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }.value
    }
}


/// Optional Unreal controls grouped by the feature they affect. Keeping them
/// off the main game page makes routine graphics settings easier to find.
/// These bindings use the existing TLAppSettings storage, not new preferences.
private struct TLGameAdvancedSettingsView: View {
    @Binding var settings: TLAppSettings
    let appID: String
    let automaticDuoActive: Bool
    var dungeons = false

    @State private var efficiencySheet = false
    @State private var metricKitSheet = false

    var body: some View {
        HuskForm {
            if !dungeons {
            Section {
                Toggle("MetalFX Spatial (Experimental)", isOn: $settings.spatialUpscaling)
                if settings.spatialUpscaling {
                    Picker("MetalFX Input Budget", selection: $settings.spatialInputPercent) {
                        ForEach([80, 85, 90, 95], id: \.self) { percent in
                            Text("\(percent)% of output dimensions").tag(percent)
                        }
                    }
                }
                Toggle("Render Target Inventory (Diagnostic)", isOn: $settings.renderTargetInventory)
            } header: {
                Text("Upscaling & Rendering")
            } footer: {
                Text("MetalFX renders at a smaller input size and upscales the image, including HUD text. Render Target Inventory logs image sizes to help diagnose it. Both require a restart; results and energy savings are unverified.")
            }

            }
            Section {
                Picker("Worker Scheduling", selection: $settings.workerScheduling) {
                    ForEach(TLAppSettings.WorkerScheduling.allCases) { Text($0.title).tag($0) }
                }
                Toggle(dungeons ? "Engine-only limiter comparison" : "Engine-only 60 FPS Limiter (Diagnostic)", isOn: $settings.engineOnlyLimiter)
                if dungeons {
                    if !settings.metal4Renderer && !settings.frameGeneration {
                        Picker("Clock experiment", selection: Binding(get: { settings.clockPresentation && settings.feedbackClockCorrection ? 3 : (settings.clockPresentation ? 2 : (settings.feedbackClockCorrection ? 1 : 0)) }, set: {
                            settings.feedbackClockCorrection = $0 == 1 || $0 == 3
                            settings.clockPresentation = $0 == 2 || $0 == 3
                        })) {
                            Text("Off").tag(0); Text("Guest feedback").tag(1); Text("Clock presentation").tag(2)
                            if settings.clockPresentation && settings.feedbackClockCorrection { Text("Legacy combined values").tag(3) }
                        }
                    }
                } else {
                    Toggle("Guest-Clock Feedback Only (Experimental)", isOn: $settings.feedbackClockCorrection)
                    Toggle("Clock-Correct Presentation (Experimental)", isOn: $settings.clockPresentation)
                }
            } header: {
                Text("Frame Pacing & CPU")
            } footer: {
                Text("Worker policies change scheduling, not fixed CPU-core affinity. The limiter compares engine-only pacing with the normal host limit; thermal safeguards stay active. Clock modes are experimental. Test each separately and restart.")
            }

            Section {
                if !dungeons || !settings.metal4Renderer {
                Picker("Vulkan Submission", selection: $settings.vulkanSubmission) {
                    ForEach(TLAppSettings.VulkanSubmission.allCases) { Text($0.title).tag($0) }
                }
                Picker("Metal Command Preparation (Experimental)", selection: $settings.execution.prefill) {
                    Text("Driver Default").tag(-1)
                    Text("At Queue Submission").tag(0)
                    Text("At End of Recording").tag(1)
                    Text("During Recording").tag(2)
                }
                Picker("Active Metal Buffer Limit (Experimental)", selection: $settings.execution.commandBufferLimit) {
                    Text("Driver Default").tag(0)
                    ForEach([8, 16, 32, 64], id: \.self) { Text("\($0) per queue").tag($0) }
                }
                }
                Picker("Swapchain Images (Experimental)", selection: $settings.execution.swapchainImages) {
                    Text("Game Default").tag(0)
                    Text("Two Images").tag(2)
                    Text("Three Images").tag(3)
                }
                Toggle("Block During Initialization Waits (Experimental)", isOn: $settings.execution.initializationParking)
            } header: {
                Text("Vulkan & GPU Queues")
            } footer: {
                Text("Defaults preserve the normal driver. Swapchain overrides apply only inside the surface's reported limits. Queue and wait settings can affect stability or memory, so compare one at a time after a full restart.")
            }

            if dungeons {
                if !settings.metal4Renderer {
                    Section("Cache Comparison") {
                        Toggle("Driver-only cache comparison", isOn: Binding(get: { settings.nativePipelineArchiveMode == 1 }, set: { settings.nativePipelineArchiveMode = $0 ? 1 : 0 }))
                    }
                }
            } else {
            Section {
                Picker("Native Pipeline Cache (Experimental)", selection: $settings.nativePipelineArchiveMode) {
                    Text("Off").tag(0)
                    Text("Driver Only · Comparison").tag(1)
                    Text("Archive Enabled").tag(2)
                }
                Toggle("Verify Native Archive Reuse (Diagnostic)", isOn: $settings.nativeArchiveVerification)
                    .disabled(settings.nativePipelineArchiveMode != 2)
                Toggle("Pipeline Identification (Diagnostic)", isOn: $settings.pipelineIdentification)
                Toggle("Pipeline Creation Feedback (Diagnostic)", isOn: $settings.pipelineFeedback)
                    .disabled(!settings.pipelineIdentification)
            } header: {
                Text("Pipeline Cache & Diagnostics")
            } footer: {
                Text("Archive Enabled stores native pipeline work where supported. MoltenVK preparation is in Efficiency Test. Leave detailed diagnostics off outside a short test.")
            }

            Section {
                Toggle("Driver Phase Profiling (Diagnostic)", isOn: $settings.driverPhaseProfiling)
                Button("Performance & Efficiency Diagnostics") { efficiencySheet = true }
                    .sheet(isPresented: $efficiencySheet) { EfficiencyDiagnosticsView() }
                Button("Delayed OS Reports (MetricKit)") { metricKitSheet = true }
                    .sheet(isPresented: $metricKitSheet) { EfficiencyMetricKitView() }
            } header: {
                Text("General Game Diagnostics")
            } footer: {
                Text("Collect general performance evidence here. Driver profiling adds overhead; MetricKit reports can arrive later. Full crash reports and device checks are in Husk Settings > Diagnostics & Logs.")
            }
            }
        }
        .huskForm()
        .disabled(automaticDuoActive)
        .navigationTitle(dungeons ? "Developer Experiments" : "Advanced & Diagnostics")
        .onChange(of: settings) { $0.save(appID) }
    }
}

/// Offline layout editor: does not register a guest controller or load a game.
private struct DungeonsPadLayoutEditor: View {
    let appID: String
    @StateObject private var pad = VirtualPad()
    @State private var layout = PadLayout()
    @State private var selected: String?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VirtualPadView(pad: pad, haptics: false, layout: layout, editing: true, connectToGame: false, selected: $selected,
                           onChange: { layout = $0; layout.save(appID) })
            VStack(spacing: 8) {
                if let id = selected {
                    Text(PadLayout.name(id))
                    Slider(value: Binding(get: { Double(layout[id].scale) }, set: { layout[id].scale = CGFloat($0); layout.save(appID) }), in: 0.6...1.8)
                        .frame(width: 180)
                    Button(layout[id].hidden ? "Show control" : "Hide control") { layout[id].hidden.toggle(); layout.save(appID) }
                    Button("Reset control") { layout[id] = PadLayout.Adjust(); layout.save(appID) }
                } else {
                    Text("Drag a control, or tap it to resize or hide it.").multilineTextAlignment(.center).frame(width: 200)
                }
                Button("Reset layout", role: .destructive) { layout = PadLayout(); selected = nil; layout.save(appID) }
            }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .navigationTitle("Controller Layout")
        .onAppear { layout = PadLayout.load(appID); HuskOrientation.set(.landscape) }
        .onDisappear { HuskOrientation.set(HuskOrientation.standard) }
    }
}
