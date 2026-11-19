// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
#if canImport(UIKit)
import UIKit
import Metal
#endif

/// A conservative launch profile, not a measured visual/energy optimum.
/// Match the published inner panel on real iPhone hardware, without guessing
/// an undocumented model identifier or trusting the phone/tablet UI idiom.
enum DuoDisplayPolicy {
    struct Metrics {
        var pointWidth: Double, pointHeight: Double
        var nativeWidth: Double, nativeHeight: Double
        var phoneHardware: Bool

        var valid: Bool {
            [pointWidth, pointHeight, nativeWidth, nativeHeight].allSatisfy { $0.isFinite && $0 > 0 && $0 <= 16384 }
        }
        var isInner: Bool {
            valid && phoneHardware && abs(min(nativeWidth, nativeHeight) - 1878) <= 1
                && abs(max(nativeWidth, nativeHeight) - 2670) <= 1
        }
        /// Physical panel pixels per UIKit point; UIKit's logical scale can
        /// exceed this on Duo. Never equate a screenshot's size with the panel.
        func scale(percent: Int = 0) -> Double? {
            guard isInner else { return nil }
            let longer = max(nativeWidth, nativeHeight), shorter = min(nativeWidth, nativeHeight)
            let physicalScale = min(longer / max(pointWidth, pointHeight), shorter / min(pointWidth, pointHeight))
            let fraction = (65...100).contains(percent) ? Double(percent) / 100
                : min(1, min(2048 / longer, 1280 / shorter))
            let result = physicalScale * fraction
            return result.isFinite && result > 0 ? result : nil
        }
        func automatic(enabled: Bool, efficientDungeons: Bool, windowed: Bool) -> Bool {
            enabled && efficientDungeons && !windowed && isInner
        }
    }
    // Balanced Apple MetalFX spatial input for the inner display; the game's
    // real render rate remains 60 FPS, never old 30→60 synthetic framegen.
    static let inputPercent = 60
    static let fps = 60
    static let worker = 2 // Balanced: preserves critical roles, no core affinity.
    static let submission = 0 // Driver Default.
    /// These are distinct backends. Resolve legacy conflicting flags in favour
    /// of the explicitly requested native Metal 4 renderer, never silent FG fallback.
    static func usesFrameGeneration(metal4: Bool, requested: Bool, metal4Bridge: Bool = false) -> Bool {
        requested && (!metal4 || metal4Bridge)
    }

    /// Runtime-matched A20 family. Prefer a validated kernel topology over a model fallback.
    /// A worker allowance is not P-core affinity.
    static func fastWorkerBudget(gpuName: String, cpuCount: Int, enabled: Bool = true,
                                 performanceCores: Int = 0, efficiencyCores: Int = 0) -> Int {
        let name = gpuName.lowercased().filter { $0.isLetter || $0.isNumber }
        guard enabled, ["applea20gpu", "applea20", "applea20progpu", "applea20pro"].contains(name) else { return 0 }
        if (2...256).contains(cpuCount), performanceCores > 0, performanceCores <= 4,
           efficiencyCores > 0, efficiencyCores < cpuCount, performanceCores + efficiencyCores == cpuCount {
            return performanceCores
        }
        // Retain the existing documented A20 Pro six-core fallback only when neither count is available.
        return performanceCores == 0 && efficiencyCores == 0 && cpuCount == 6 &&
            ["applea20progpu", "applea20pro"].contains(name) ? 2 : 0
    }
    static func workerPolicy(gpuName: String, cpuCount: Int, enabled: Bool = true,
                             performanceCores: Int = 0, efficiencyCores: Int = 0) -> Int {
        fastWorkerBudget(gpuName: gpuName, cpuCount: cpuCount, enabled: enabled,
                         performanceCores: performanceCores, efficiencyCores: efficiencyCores) > 0 ? 4 : worker
    }

#if canImport(UIKit)
    @MainActor static let detectedGPUName: String = MTLCreateSystemDefaultDevice()?.name ?? ""
    @MainActor static let runtimeCoreCounts: (performance: Int, efficiency: Int) = {
        var info = tl_host_cpu_info(); tl_host_cpu_topology(&info)
        guard Int(info.total) == ProcessInfo.processInfo.processorCount else { return (0, 0) }
        return (Int(info.performance), Int(info.efficiency))
    }()
    @MainActor static var supportsA20Workers: Bool {
        fastWorkerBudget(gpuName: detectedGPUName, cpuCount: ProcessInfo.processInfo.processorCount,
                         performanceCores: runtimeCoreCounts.performance, efficiencyCores: runtimeCoreCounts.efficiency) > 0
    }
    @MainActor static func metrics(screen: UIScreen) -> Metrics {
        Metrics(pointWidth: Double(screen.bounds.width), pointHeight: Double(screen.bounds.height),
                nativeWidth: Double(screen.nativeBounds.width), nativeHeight: Double(screen.nativeBounds.height),
                phoneHardware: EfficiencyHardware.identifier().hasPrefix("iPhone"))
    }
#endif
}
