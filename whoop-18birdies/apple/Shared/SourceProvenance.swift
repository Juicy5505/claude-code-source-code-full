import Foundation

enum MetricSource: String, Codable, CaseIterable, Hashable, Sendable {
    case whoopCloud
    case whoopBroadcast
    case whoopMotion
    case appleWatch
    case iphoneGPS
    case healthKit
    case manual
    case derived
    case demo

    var title: String {
        switch self {
        case .whoopCloud: "WHOOP Cloud"
        case .whoopBroadcast: "WHOOP Broadcast"
        case .whoopMotion: "WHOOP 5 Motion"
        case .appleWatch: "Apple Watch"
        case .iphoneGPS: "iPhone GPS"
        case .healthKit: "Apple Health"
        case .manual: "Manual"
        case .derived: "In-house model"
        case .demo: "Demo"
        }
    }

    var symbol: String {
        switch self {
        case .whoopCloud: "cloud.fill"
        case .whoopBroadcast: "wave.3.right"
        case .whoopMotion: "gyroscope"
        case .appleWatch: "applewatch"
        case .iphoneGPS: "location.fill"
        case .healthKit: "heart.fill"
        case .manual: "hand.tap.fill"
        case .derived: "function"
        case .demo: "sparkles"
        }
    }
}

enum DataQuality: String, Codable, Hashable, Sendable {
    case verified
    case estimated
    case stale
    case unavailable
}

struct DataProvenance: Codable, Hashable, Sendable {
    let source: MetricSource
    let observedAt: Date
    let receivedAt: Date
    let quality: DataQuality
    let algorithmVersion: String?
    let inputSources: [MetricSource]

    init(
        source: MetricSource,
        observedAt: Date,
        receivedAt: Date = .now,
        quality: DataQuality,
        algorithmVersion: String? = nil,
        inputSources: [MetricSource] = []
    ) {
        self.source = source
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.quality = quality
        self.algorithmVersion = algorithmVersion
        self.inputSources = inputSources
    }
}
