import Foundation

/// A point in authoring grid space. Fractional values are allowed so props can
/// sit between cells without inventing a second coordinate system.
public struct CellPoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ x: Double, _ y: Double) {
        self.init(x: x, y: y)
    }

    public static let zero = CellPoint(x: 0, y: 0)

    public func offset(dx: Double = 0, dy: Double = 0) -> CellPoint {
        CellPoint(x: x + dx, y: y + dy)
    }

    public func distance(to other: CellPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// A size in authoring grid space.
public struct CellSize: Codable, Sendable, Equatable, Hashable {
    public var width: Double
    public var depth: Double

    public init(width: Double, depth: Double) {
        self.width = width
        self.depth = depth
    }
}

/// An axis-aligned rectangle in authoring grid space.
public struct CellRect: Codable, Sendable, Equatable, Hashable {
    public var origin: CellPoint
    public var size: CellSize

    public init(origin: CellPoint, size: CellSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, depth: Double) {
        self.init(origin: CellPoint(x: x, y: y), size: CellSize(width: width, depth: depth))
    }

    public var minX: Double { min(origin.x, origin.x + size.width) }
    public var maxX: Double { max(origin.x, origin.x + size.width) }
    public var minY: Double { min(origin.y, origin.y + size.depth) }
    public var maxY: Double { max(origin.y, origin.y + size.depth) }

    public var center: CellPoint {
        CellPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    public func contains(_ point: CellPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

/// A point in RealityKit world space, in meters. +Y is up.
public struct WorldPoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = WorldPoint(x: 0, y: 0, z: 0)
}

/// A heterogeneous configuration value, used by prop instances to override
/// prototype defaults without inventing a bespoke type per mechanic.
public enum LevelValue: Codable, Sendable, Equatable, Hashable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported LevelValue"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
