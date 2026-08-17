import Foundation
import Metal
import OSLog

/// Visual tier chosen from what the device can actually do.
///
/// The deployment target is an API floor, not an art budget. iOS 18 is the
/// oldest OS the game runs on; it says nothing about how good the game looks.
/// Everything here scales *up* on capable hardware — the baseline is the full
/// visual target, and nothing in the art direction, level complexity or gameplay
/// is cut to accommodate older devices.
public enum RenderQuality: String, Sendable, CaseIterable, Comparable {
    /// Older A-series hardware: fewer dynamic lights, cheaper shadows.
    case baseline
    /// The common case.
    case standard
    /// Recent hardware: every practical light, highest shadow quality.
    case high

    public static func < (lhs: RenderQuality, rhs: RenderQuality) -> Bool {
        let order: [RenderQuality] = [.baseline, .standard, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    /// How many practical (point) lights to place.
    public var practicalLightBudget: Int {
        switch self {
        case .baseline: 2
        case .standard: 4
        case .high: 8
        }
    }

    /// Whether the key light casts dynamic shadows.
    ///
    /// Shadows are what stop a top-down orthographic view reading flat, so they
    /// stay on everywhere; only their cost is tuned.
    public var castsShadows: Bool { true }

    /// Depth bias for the shadow map. Lower is crisper.
    public var shadowDepthBias: Float {
        switch self {
        case .baseline: 2.5
        case .standard: 1.5
        case .high: 1.0
        }
    }

    /// Picks a tier from the GPU family and available memory.
    ///
    /// Errs upward: a device that reports nothing useful gets `.standard`
    /// rather than the cut-down tier.
    public static func recommended() -> RenderQuality {
        let log = Logger(subsystem: "com.exrector.DerClou", category: "quality")

        #if targetEnvironment(simulator)
        // The simulator's GPU does not report device families the way hardware
        // does, and would otherwise be graded down to the cut-back tier — which
        // is the last thing wanted while judging how the game looks.
        log.info("Simulator: forcing high quality")
        return .high
        #else
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.info("No Metal device; assuming standard quality")
            return .standard
        }

        let memory = ProcessInfo.processInfo.physicalMemory
        let gigabytes = Double(memory) / 1_073_741_824

        let quality: RenderQuality
        if device.supportsFamily(.apple8), gigabytes >= 5.5 {
            quality = .high
        } else if device.supportsFamily(.apple6) {
            quality = .standard
        } else {
            quality = .baseline
        }

        log.info("""
            Render quality \(quality.rawValue, privacy: .public) \
            (\(device.name, privacy: .public), \(gigabytes, privacy: .public) GB)
            """)
        return quality
        #endif
    }
}
