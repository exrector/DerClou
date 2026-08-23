import Foundation

/// How authored mesh bounds are normalized into a reusable gameplay prototype.
public enum AssetScalePolicy: String, Codable, Sendable, CaseIterable {
    /// Source units are already meters; only the pivot is normalized.
    case preserveMeters
    /// Independent axes exactly fill the canonical gameplay bounds.
    case fitCanonicalBounds
    /// One uniform scale fits inside the canonical bounds without distortion.
    case uniformFit
}

/// The point in source art that is placed at `PropSpec.position`.
public enum PlacementPivot: String, Codable, Sendable, CaseIterable {
    case bottomCenter
    case center
    case hingeLeft
    case hingeRight
}

/// Different consumers need different boundaries around the same object.
/// Keeping them together prevents render bounds from accidentally becoming
/// navigation, interaction, or actor-body authority.
public struct ObjectClearances: Codable, Sendable, Equatable {
    public var collisionMargin: Double
    public var navigationMargin: Double
    public var interactionStandoff: Double
    public var doorSweepMargin: Double
    public var actorSeparation: Double

    public init(
        collisionMargin: Double = 0,
        navigationMargin: Double = 0,
        interactionStandoff: Double = 0.55,
        doorSweepMargin: Double = 0.05,
        actorSeparation: Double = 0.04
    ) {
        self.collisionMargin = collisionMargin
        self.navigationMargin = navigationMargin
        self.interactionStandoff = interactionStandoff
        self.doorSweepMargin = doorSweepMargin
        self.actorSeparation = actorSeparation
    }
}

/// Permanent modular-grid contract for one reusable prototype.
public struct PlacementContract: Codable, Sendable, Equatable {
    /// Translation increment in authoring cells (not meters).
    public var positionSnapCells: Double
    public var rotationSnapDegrees: Double
    public var pivot: PlacementPivot
    public var scalePolicy: AssetScalePolicy
    public var clearances: ObjectClearances

    public init(
        positionSnapCells: Double = 0.05,
        rotationSnapDegrees: Double = 15,
        pivot: PlacementPivot = .bottomCenter,
        scalePolicy: AssetScalePolicy = .uniformFit,
        clearances: ObjectClearances = .init()
    ) {
        self.positionSnapCells = positionSnapCells
        self.rotationSnapDegrees = rotationSnapDegrees
        self.pivot = pivot
        self.scalePolicy = scalePolicy
        self.clearances = clearances
    }

    public func snapped(_ point: CellPoint) -> CellPoint {
        guard positionSnapCells > 0 else { return point }
        return CellPoint(
            (point.x / positionSnapCells).rounded() * positionSnapCells,
            (point.y / positionSnapCells).rounded() * positionSnapCells
        )
    }

    public func snappedRotation(_ degrees: Double) -> Double {
        guard rotationSnapDegrees > 0 else { return degrees }
        return (degrees / rotationSnapDegrees).rounded() * rotationSnapDegrees
    }

    public func isAligned(_ point: CellPoint, tolerance: Double = 1e-9) -> Bool {
        let resolved = snapped(point)
        return abs(resolved.x - point.x) <= tolerance && abs(resolved.y - point.y) <= tolerance
    }

    public func isRotationAligned(_ degrees: Double, tolerance: Double = 1e-9) -> Bool {
        abs(snappedRotation(degrees) - degrees) <= tolerance
    }
}

public struct MetricSize3D: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var depth: Double

    public init(width: Double, height: Double, depth: Double) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

/// Pure normalization math shared by import tools and runtime asset validation.
public enum AssetNormalizer {
    public static func scale(
        source: MetricSize3D,
        target: MetricSize3D,
        policy: AssetScalePolicy
    ) -> MetricSize3D? {
        guard source.width > 0, source.height > 0, source.depth > 0,
              target.width > 0, target.height > 0, target.depth > 0 else { return nil }
        switch policy {
        case .preserveMeters:
            return MetricSize3D(width: 1, height: 1, depth: 1)
        case .fitCanonicalBounds:
            return MetricSize3D(
                width: target.width / source.width,
                height: target.height / source.height,
                depth: target.depth / source.depth
            )
        case .uniformFit:
            let factor = min(
                target.width / source.width,
                target.height / source.height,
                target.depth / source.depth
            )
            return MetricSize3D(width: factor, height: factor, depth: factor)
        }
    }
}

