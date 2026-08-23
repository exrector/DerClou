import Foundation

/// Typed facts that autonomous agents may react to. A stimulus reports what
/// happened and where; it never moves an agent or controls mission time itself.
public enum StimulusKind: String, Codable, Sendable, CaseIterable {
    case guardVisualContact
    case cameraVisualContact
    case sound
    case forcedEntry
    case unexpectedWorldState
    case securityAlarm
}

public struct PerceptionStimulus: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: StimulusKind
    public var sourceID: String
    public var targetID: String?
    public var location: WorldPoint
    public var missionTime: Double
    /// Normalized signal strength after distance/occlusion has been evaluated.
    public var intensity: Double

    public init(
        id: String,
        kind: StimulusKind,
        sourceID: String,
        targetID: String? = nil,
        location: WorldPoint,
        missionTime: Double,
        intensity: Double
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.targetID = targetID
        self.location = location
        self.missionTime = missionTime
        self.intensity = min(1, max(0, intensity))
    }
}

public enum AlertLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case calm
    case suspicious
    case investigating
    case alerted
    case lockdown

    public static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Data-driven conversion from heterogeneous stimuli to one readable alert
/// scale. Values are deliberately deterministic: no random hearing/detection.
public struct AlertPolicy: Sendable, Equatable {
    public var stimulusWeights: [StimulusKind: Double]
    public var suspiciousThreshold: Double
    public var investigatingThreshold: Double
    public var alertedThreshold: Double
    public var lockdownThreshold: Double
    public var decayPerSecond: Double

    public init(
        stimulusWeights: [StimulusKind: Double],
        suspiciousThreshold: Double = 0.15,
        investigatingThreshold: Double = 0.4,
        alertedThreshold: Double = 0.7,
        lockdownThreshold: Double = 0.95,
        decayPerSecond: Double = 0.015
    ) {
        self.stimulusWeights = stimulusWeights
        self.suspiciousThreshold = suspiciousThreshold
        self.investigatingThreshold = investigatingThreshold
        self.alertedThreshold = alertedThreshold
        self.lockdownThreshold = lockdownThreshold
        self.decayPerSecond = max(0, decayPerSecond)
    }

    public static let standard = AlertPolicy(stimulusWeights: [
        .guardVisualContact: 1.0,
        .cameraVisualContact: 0.9,
        .sound: 0.65,
        .forcedEntry: 0.75,
        .unexpectedWorldState: 0.45,
        .securityAlarm: 1.0
    ])
}

public struct AlertState: Sendable, Equatable {
    public private(set) var value: Double
    public private(set) var lastUpdatedAt: Double
    public private(set) var lastStimulusID: String?

    public init(value: Double = 0, lastUpdatedAt: Double = 0, lastStimulusID: String? = nil) {
        self.value = min(1, max(0, value))
        self.lastUpdatedAt = max(0, lastUpdatedAt)
        self.lastStimulusID = lastStimulusID
    }

    public func level(policy: AlertPolicy = .standard) -> AlertLevel {
        if value >= policy.lockdownThreshold { return .lockdown }
        if value >= policy.alertedThreshold { return .alerted }
        if value >= policy.investigatingThreshold { return .investigating }
        if value >= policy.suspiciousThreshold { return .suspicious }
        return .calm
    }

    public mutating func observe(_ stimulus: PerceptionStimulus, policy: AlertPolicy = .standard) {
        decay(to: stimulus.missionTime, policy: policy)
        value = min(1, value + stimulus.intensity * (policy.stimulusWeights[stimulus.kind] ?? 0))
        lastStimulusID = stimulus.id
    }

    public mutating func decay(to missionTime: Double, policy: AlertPolicy = .standard) {
        guard missionTime > lastUpdatedAt else { return }
        value = max(0, value - (missionTime - lastUpdatedAt) * policy.decayPerSecond)
        lastUpdatedAt = missionTime
    }
}

/// Intent selected from a stimulus. Navigation resolves the goal from the
/// agent's current position; no waypoint route is authored into the intent.
public enum AgentGoal: Sendable, Equatable {
    case move(destination: WorldPoint)
    case interact(objectID: String, location: WorldPoint)
    case resumePatrol(routeID: String, routeTime: Double, location: WorldPoint)
    case patrol(routeID: String)
    case investigate(stimulusID: String, location: WorldPoint)
    case pursue(targetID: String, lastKnownLocation: WorldPoint)
    case secure(objectID: String, location: WorldPoint)
}

public enum GuardDecisionPolicy {
    public static func goal(
        for stimulus: PerceptionStimulus,
        currentPatrolID: String,
        alertPolicy: AlertPolicy = .standard
    ) -> AgentGoal {
        if stimulus.kind == .guardVisualContact, let targetID = stimulus.targetID {
            return .pursue(targetID: targetID, lastKnownLocation: stimulus.location)
        }

        let urgency = stimulus.intensity * (alertPolicy.stimulusWeights[stimulus.kind] ?? 0)
        if urgency >= alertPolicy.suspiciousThreshold {
            return .investigate(stimulusID: stimulus.id, location: stimulus.location)
        }
        return .patrol(routeID: currentPatrolID)
    }
}
