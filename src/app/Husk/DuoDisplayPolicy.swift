// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
#if canImport(UIKit)
import UIKit
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
    static let inputPercent = 80
    static let fps = 60
    static let worker = 2 // Balanced: preserves critical roles, no core affinity.
    static let submission = 0 // Driver Default.

#if canImport(UIKit)
    @MainActor static func metrics(screen: UIScreen) -> Metrics {
        Metrics(pointWidth: Double(screen.bounds.width), pointHeight: Double(screen.bounds.height),
                nativeWidth: Double(screen.nativeBounds.width), nativeHeight: Double(screen.nativeBounds.height),
                phoneHardware: EfficiencyHardware.identifier().hasPrefix("iPhone"))
    }
#endif
}
