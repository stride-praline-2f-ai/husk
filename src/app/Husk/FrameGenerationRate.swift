// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Rate of actual drawable presentation callbacks, including generated/fallback
/// images. Separate from game rendering, unique images and input responsiveness.
struct FrameGenerationRate {
    private var previous: (time: Double, real: UInt64, generated: UInt64, resets: UInt64)?
    mutating func sample(time: Double, real: UInt64, generated: UInt64, resets: UInt64) -> Double? {
        guard time.isFinite && time > 0 else { previous = nil; return nil }
        let old = previous
        previous = (time, real, generated, resets)
        guard let old, old.resets == resets, real >= old.real, generated >= old.generated else { return nil }
        let elapsed = time - old.time
        guard elapsed >= 0.25 && elapsed <= 3 else { return nil }
        let rate = (Double(real - old.real) + Double(generated - old.generated)) / elapsed
        return rate.isFinite && rate >= 0 && rate <= 360 ? rate : nil
    }
    mutating func reset() { previous = nil }
}
