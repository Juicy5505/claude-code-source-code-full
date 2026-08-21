import Foundation

struct LocationFix: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double
    let capturedAt: Date
    let provenance: DataProvenance

    var isUsableForShotDistance: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        horizontalAccuracyMeters >= 0 && horizontalAccuracyMeters <= 25
    }
}

/// A location captured alongside a swing observation.
///
/// Unlike `LocationFix`, horizontal accuracy is optional because external
/// swing sources do not all report it. The observation is still retained when
/// accuracy is absent, but distance derivation must quality-gate it rather
/// than inventing a precision value.
struct SwingLocationObservation: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double?
    let capturedAt: Date
    let provenance: DataProvenance

    var hasValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

enum SwingShotDistanceStatus: String, Codable, Hashable, Sendable {
    case measured
    case missingLocation
    case missingHorizontalAccuracy
    case staleLocation
    case lowHorizontalAccuracy
    case nonIncreasingTimestamps
}

enum SwingShotIntervalExclusionReason: String, Codable, Hashable, Sendable {
    /// The destination swing is assigned to another hole, so the intervening
    /// walk/ride is deliberately not presented as shot distance.
    case confirmedHoleTransition
    /// Available evidence suggests a hole boundary but is not strong enough
    /// for autonomous assignment. Distance stays withheld until review.
    case possibleHoleTransition
    /// Coordinates were present but did not identify a real spatial provider.
    /// WHOOP motion provenance alone is not GPS provenance.
    case unverifiedSpatialSource
}

enum SwingLocationCorrelationMethod: String, Codable, Hashable, Sendable {
    case sensorSynchronized
    case nearestTimelineFix
    case interpolatedTimelineFix
}

/// A shot-like interval inferred from two consecutive swing observations.
///
/// This is straight-line displacement between the two swing locations. It is
/// deliberately not named or presented as ball carry or a spatial club path.
struct SwingShotInterval: Codable, Hashable, Sendable {
    let finalizedBySwingID: UUID
    let finalizedAt: Date
    let elapsedSeconds: Double
    let straightLineDisplacementYards: Double?
    let distanceUncertaintyYards: Double?
    let distanceStatus: SwingShotDistanceStatus
    /// Orthogonal to GPS quality: a valid coordinate pair can still be
    /// excluded because it spans a confirmed or reviewable hole boundary.
    let exclusionReason: SwingShotIntervalExclusionReason?
    let provenance: DataProvenance

    var quality: DataQuality { provenance.quality }
    var algorithmVersion: String? { provenance.algorithmVersion }

    init(
        finalizedBySwingID: UUID,
        finalizedAt: Date,
        elapsedSeconds: Double,
        straightLineDisplacementYards: Double?,
        distanceUncertaintyYards: Double?,
        distanceStatus: SwingShotDistanceStatus,
        exclusionReason: SwingShotIntervalExclusionReason? = nil,
        provenance: DataProvenance
    ) {
        self.finalizedBySwingID = finalizedBySwingID
        self.finalizedAt = finalizedAt
        self.elapsedSeconds = elapsedSeconds
        self.straightLineDisplacementYards = straightLineDisplacementYards
        self.distanceUncertaintyYards = distanceUncertaintyYards
        self.distanceStatus = distanceStatus
        self.exclusionReason = exclusionReason
        self.provenance = provenance
    }
}

struct GolfSwingMetrics: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let capturedAt: Date
    let peakG: Double
    let backswingSeconds: Double?
    let downswingSeconds: Double?
    let tempoRatio: Double?
    let heartRateBPM: Int?
    /// Confidence emitted by a derived swing detector, when that source
    /// provides one. Older persisted rounds omit this optional field and
    /// continue to decode unchanged.
    let detectionConfidence: Double?
    /// Experimental WHOOP wrist-rotation analysis retained from a reviewed
    /// motion import. This is not a clubhead or ball-flight measurement.
    let wristAnalysis: WhoopMotionWristAnalysis?
    /// Mount-corrected downswing yaw from Watch analysis (positive = in-to-out).
    /// Optional so older rounds decode unchanged. Not clubhead path.
    let pathYawDegrees: Double?
    /// Body-relative path class string matching `SwingPathClass.rawValue`.
    let pathClass: String?
    let provenance: DataProvenance
    let location: SwingLocationObservation?
    let locationCorrelationMethod: SwingLocationCorrelationMethod?
    var shotInterval: SwingShotInterval?

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        peakG: Double,
        backswingSeconds: Double? = nil,
        downswingSeconds: Double? = nil,
        tempoRatio: Double? = nil,
        heartRateBPM: Int? = nil,
        detectionConfidence: Double? = nil,
        wristAnalysis: WhoopMotionWristAnalysis? = nil,
        pathYawDegrees: Double? = nil,
        pathClass: String? = nil,
        provenance: DataProvenance,
        location: SwingLocationObservation? = nil,
        locationCorrelationMethod: SwingLocationCorrelationMethod? = nil,
        shotInterval: SwingShotInterval? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.peakG = peakG
        self.backswingSeconds = backswingSeconds
        self.downswingSeconds = downswingSeconds
        self.tempoRatio = tempoRatio
        self.heartRateBPM = heartRateBPM
        self.detectionConfidence = detectionConfidence
        self.wristAnalysis = wristAnalysis
        self.pathYawDegrees = pathYawDegrees
        self.pathClass = pathClass
        self.provenance = provenance
        self.location = location
        self.locationCorrelationMethod = locationCorrelationMethod
        self.shotInterval = shotInterval
    }

    /// Parsed body-relative path class, or `.unknown` when absent/unrecognized.
    var resolvedPathClass: SwingPathClass {
        guard let pathClass, let resolved = SwingPathClass(rawValue: pathClass) else {
            return .unknown
        }
        return resolved
    }
}

struct ShotRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let sequence: Int
    let hole: Int
    let capturedAt: Date
    let location: LocationFix
    var distanceToNextYards: Double?
    var distanceUncertaintyYards: Double?

    // These fields exist only long enough for GolfRound's v1 decoder to move a
    // segment from the later location onto the shot that produced it.
    private var legacyDistanceFromPreviousYards: Double?
    private var legacyUncertaintyYards: Double?

    init(
        id: UUID = UUID(),
        sequence: Int,
        hole: Int,
        capturedAt: Date,
        location: LocationFix,
        distanceToNextYards: Double? = nil,
        distanceUncertaintyYards: Double? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.hole = hole
        self.capturedAt = capturedAt
        self.location = location
        self.distanceToNextYards = distanceToNextYards
        self.distanceUncertaintyYards = distanceUncertaintyYards
        self.legacyDistanceFromPreviousYards = nil
        self.legacyUncertaintyYards = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sequence
        case hole
        case capturedAt
        case location
        case distanceToNextYards
        case distanceUncertaintyYards
        case displacementFromPreviousYards
        case uncertaintyYards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sequence = try container.decode(Int.self, forKey: .sequence)
        hole = try container.decode(Int.self, forKey: .hole)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        location = try container.decode(LocationFix.self, forKey: .location)
        distanceToNextYards = try container.decodeIfPresent(Double.self, forKey: .distanceToNextYards)
        distanceUncertaintyYards = try container.decodeIfPresent(
            Double.self,
            forKey: .distanceUncertaintyYards
        )
        legacyDistanceFromPreviousYards = try container.decodeIfPresent(
            Double.self,
            forKey: .displacementFromPreviousYards
        )
        legacyUncertaintyYards = try container.decodeIfPresent(Double.self, forKey: .uncertaintyYards)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(hole, forKey: .hole)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(distanceToNextYards, forKey: .distanceToNextYards)
        try container.encodeIfPresent(distanceUncertaintyYards, forKey: .distanceUncertaintyYards)
    }

    fileprivate mutating func consumeLegacySegment() -> (distance: Double?, uncertainty: Double?) {
        defer {
            legacyDistanceFromPreviousYards = nil
            legacyUncertaintyYards = nil
        }
        return (legacyDistanceFromPreviousYards, legacyUncertaintyYards)
    }
}

enum GolfHoleCount: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case nine = 9
    case eighteen = 18

    var id: Int { rawValue }
}

enum RoundLifecycle: String, Codable, Hashable, Sendable {
    case draft
    case finished
}

enum RoundRecorder: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case whoop5
    case appleWatch
    case hybrid
    case iphone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whoop5: "WHOOP 5 + iPhone GPS"
        case .appleWatch: "Apple Watch"
        case .hybrid: "Hybrid · Apple Watch + WHOOP 5"
        case .iphone: "iPhone only"
        }
    }

    var adaptiveSensorMode: AdaptiveSensorMode? {
        switch self {
        case .whoop5: .whoopOnly
        case .appleWatch: .appleWatchOnly
        case .hybrid: .hybrid
        case .iphone: nil
        }
    }
}

struct HoleResult: Codable, Identifiable, Hashable, Sendable {
    var id: Int { number }
    let number: Int
    var par: Int?
    var strokes: Int?

    init(number: Int, par: Int? = nil, strokes: Int? = nil) {
        self.number = number
        self.par = par.map { max(3, min(6, $0)) }
        self.strokes = strokes.map { max(1, min(20, $0)) }
    }
}

/// One explicit change to the hole selected while the round was being played.
///
/// Delayed sensor imports use this persisted timeline instead of guessing a
/// hole from GPS geometry, swing count, or manual shot markers. Sequence is an
/// audit-order tiebreaker for two transitions recorded at the same instant.
struct HoleTransition: Codable, Identifiable, Hashable, Sendable {
    var id: Int { sequence }
    let sequence: Int
    let hole: Int
    let transitionedAt: Date
}

/// An append-only manual decision about one accepted swing observation.
///
/// `hole == nil` is an explicit manual unassignment. Keeping each decision,
/// rather than replacing a dictionary value, preserves when and why the latest
/// post-round correction superseded an earlier one.
struct SwingHoleCorrection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let swingID: UUID
    let hole: Int?
    let correctedAt: Date
    let provenance: DataProvenance
}

enum SwingHoleAssignmentMethod: String, Codable, Hashable, Sendable {
    case manualCorrection
    case manualUnassignment
    case roundTimeline
    case unavailable

    var displayName: String {
        switch self {
        case .manualCorrection: "Manual correction"
        case .manualUnassignment: "Manually unassigned"
        case .roundTimeline: "Round timeline"
        case .unavailable: "Outside round timeline"
        }
    }
}

struct SwingHoleAssignment: Hashable, Sendable {
    let hole: Int?
    let method: SwingHoleAssignmentMethod
    let auditedAt: Date?
}

struct GolfRound: Codable, Identifiable, Hashable, Sendable {
    static let currentSchemaVersion = 4

    private(set) var schemaVersion: Int
    let id: UUID
    var courseName: String
    let startedAt: Date
    private(set) var endedAt: Date?
    private(set) var lifecycle: RoundLifecycle
    let holeCount: GolfHoleCount
    let recordingDevice: RoundRecorder
    let timeZoneIdentifier: String
    private(set) var currentHole: Int
    private(set) var holes: [HoleResult]
    private(set) var holeTransitions: [HoleTransition]
    private(set) var swingHoleCorrections: [SwingHoleCorrection]
    var shots: [ShotRecord]
    var swings: [GolfSwingMetrics]
    var notes: String

    /// A v1 file had only one aggregate score-to-par value. It is preserved for
    /// display/migration, but never treated as a complete scorecard because the
    /// old default zero could mean either genuine even par or no entry at all.
    private(set) var legacyScoreToPar: Int?

    init(
        id: UUID = UUID(),
        courseName: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        lifecycle: RoundLifecycle = .draft,
        holeCount: GolfHoleCount = .eighteen,
        recordingDevice: RoundRecorder = .iphone,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        currentHole: Int = 1,
        holes: [HoleResult]? = nil,
        holeTransitions: [HoleTransition]? = nil,
        swingHoleCorrections: [SwingHoleCorrection] = [],
        shots: [ShotRecord] = [],
        swings: [GolfSwingMetrics] = [],
        notes: String = "",
        legacyScoreToPar: Int? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.courseName = courseName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lifecycle = lifecycle
        self.holeCount = holeCount
        self.recordingDevice = recordingDevice
        self.timeZoneIdentifier = TimeZone(identifier: timeZoneIdentifier)?.identifier
            ?? TimeZone.current.identifier
        self.holes = Self.normalizedHoles(holes ?? [], count: holeCount)
        self.currentHole = max(1, min(holeCount.rawValue, currentHole))
        self.shots = shots
        self.swings = swings
        self.holeTransitions = Self.normalizedHoleTransitions(
            holeTransitions ?? [],
            startedAt: startedAt,
            count: holeCount
        )
        self.swingHoleCorrections = Self.normalizedSwingHoleCorrections(
            swingHoleCorrections,
            swings: swings,
            count: holeCount
        )
        self.notes = notes
        self.legacyScoreToPar = legacyScoreToPar
    }

    var isFinished: Bool { lifecycle == .finished }

    var localDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startedAt)
    }

    var currentPar: Int? {
        holes[currentHole - 1].par
    }

    var currentStrokes: Int? {
        holes[currentHole - 1].strokes
    }

    var scoredHoleCount: Int {
        holes.lazy.filter { $0.strokes != nil }.count
    }

    var parredHoleCount: Int {
        holes.lazy.filter { $0.par != nil }.count
    }

    var hasCompleteStrokes: Bool {
        scoredHoleCount == holeCount.rawValue
    }

    var hasCompletePars: Bool {
        parredHoleCount == holeCount.rawValue
    }

    var isScoreComplete: Bool {
        hasCompleteStrokes && hasCompletePars
    }

    /// Official gross score is available only when every planned hole has an
    /// entered stroke count. Partial entry is exposed separately for live UI.
    var grossScore: Int? {
        guard hasCompleteStrokes else { return nil }
        return holes.compactMap(\.strokes).reduce(0, +)
    }

    var enteredStrokes: Int? {
        let values = holes.compactMap(\.strokes)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var totalPar: Int? {
        guard hasCompletePars else { return nil }
        return holes.compactMap(\.par).reduce(0, +)
    }

    var scoreToPar: Int? {
        guard let grossScore, let totalPar else { return nil }
        return grossScore - totalPar
    }

    var runningScoreToPar: Int? {
        let entered = holes.compactMap { hole -> Int? in
            guard let strokes = hole.strokes, let par = hole.par else { return nil }
            return strokes - par
        }
        return entered.isEmpty ? nil : entered.reduce(0, +)
    }

    @discardableResult
    mutating func adjustCurrentStrokes(by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let index = currentHole - 1
        let current = holes[index].strokes
        let next: Int?
        if let current {
            let candidate = current + delta
            next = candidate < 1 ? nil : min(20, candidate)
        } else {
            guard delta > 0 else { return false }
            next = 1
        }
        guard next != current else { return false }
        holes[index].strokes = next
        return true
    }

    @discardableResult
    mutating func adjustCurrentPar(by delta: Int) -> Bool {
        let index = currentHole - 1
        let next: Int
        if let current = holes[index].par {
            next = max(3, min(6, current + delta))
        } else {
            next = delta < 0 ? 3 : 4
        }
        guard next != holes[index].par else { return false }
        holes[index].par = next
        return true
    }

    @discardableResult
    mutating func moveHole(by delta: Int, at date: Date = .now) -> Bool {
        guard lifecycle == .draft,
              date >= startedAt,
              holeTransitions.last.map({ date >= $0.transitionedAt }) ?? true
        else { return false }
        let next = max(1, min(holeCount.rawValue, currentHole + delta))
        guard next != currentHole else { return false }
        currentHole = next
        holeTransitions.append(
            HoleTransition(
                sequence: holeTransitions.count + 1,
                hole: next,
                transitionedAt: date
            )
        )
        if !swings.isEmpty {
            finalizeWHOOPTriggeredShotIntervals()
        }
        return true
    }

    /// Resolves one accepted observation using explicit correction first and
    /// the round's selected-hole timeline second. A boundary transition owns
    /// observations captured at that exact timestamp.
    func holeAssignment(for swingID: UUID) -> SwingHoleAssignment? {
        guard let swing = swings.first(where: { $0.id == swingID }) else { return nil }

        if let correction = swingHoleCorrections.last(where: { $0.swingID == swingID }) {
            return SwingHoleAssignment(
                hole: correction.hole,
                method: correction.hole == nil ? .manualUnassignment : .manualCorrection,
                auditedAt: correction.correctedAt
            )
        }

        guard swing.capturedAt >= startedAt,
              endedAt.map({ swing.capturedAt <= $0 }) ?? true,
              let transition = holeTransitions.last(where: { $0.transitionedAt <= swing.capturedAt })
        else {
            return SwingHoleAssignment(hole: nil, method: .unavailable, auditedAt: nil)
        }

        return SwingHoleAssignment(
            hole: transition.hole,
            method: .roundTimeline,
            auditedAt: transition.transitionedAt
        )
    }

    /// Appends a validated manual assignment or explicit unassignment.
    @discardableResult
    mutating func setSwingHoleCorrection(
        swingID: UUID,
        hole: Int?,
        at date: Date = .now
    ) -> Bool {
        guard let swing = swings.first(where: { $0.id == swingID }),
              hole.map({ (1...holeCount.rawValue).contains($0) }) ?? true
        else { return false }
        guard swingHoleCorrections.last(where: { $0.swingID == swingID })?.hole != hole
                || !swingHoleCorrections.contains(where: { $0.swingID == swingID })
        else { return false }

        swingHoleCorrections.append(
            SwingHoleCorrection(
                id: UUID(),
                swingID: swingID,
                hole: hole,
                correctedAt: date,
                provenance: DataProvenance(
                    source: .manual,
                    observedAt: date,
                    receivedAt: date,
                    quality: .verified,
                    inputSources: [swing.provenance.source]
                )
            )
        )
        finalizeWHOOPTriggeredShotIntervals()
        return true
    }

    mutating func markFinished(at date: Date = .now) {
        lifecycle = .finished
        endedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case courseName
        case startedAt
        case endedAt
        case lifecycle
        case holeCount
        case recordingDevice
        case timeZoneIdentifier
        case currentHole
        case holes
        case holeTransitions
        case swingHoleCorrections
        case shots
        case swings
        case notes
        case legacyScoreToPar

        // v1-only keys
        case currentPar
        case scoreToPar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        schemaVersion = Self.currentSchemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        courseName = try container.decode(String.self, forKey: .courseName)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        lifecycle = try container.decodeIfPresent(RoundLifecycle.self, forKey: .lifecycle)
            ?? (endedAt == nil ? .draft : .finished)

        holeCount = try container.decodeIfPresent(GolfHoleCount.self, forKey: .holeCount) ?? .eighteen
        recordingDevice = try container.decodeIfPresent(
            RoundRecorder.self,
            forKey: .recordingDevice
        ) ?? .iphone
        let decodedTimeZone = try container.decodeIfPresent(
            String.self,
            forKey: .timeZoneIdentifier
        )
        timeZoneIdentifier = decodedTimeZone.flatMap(TimeZone.init(identifier:))?.identifier
            ?? TimeZone.current.identifier
        let decodedCurrentHole = try container.decodeIfPresent(Int.self, forKey: .currentHole) ?? 1
        currentHole = max(1, min(holeCount.rawValue, decodedCurrentHole))

        let decodedHoles = try container.decodeIfPresent([HoleResult].self, forKey: .holes) ?? []
        // Schema 1/2 implicitly filled unknown pars with 4, so their values
        // cannot be distinguished from an actual user entry. Preserve strokes
        // but reset pars to unknown rather than treating fabricated par 72/36
        // as an official scorecard.
        let trustworthyHoles = decodedVersion >= 3
            ? decodedHoles
            : decodedHoles.map { HoleResult(number: $0.number, par: nil, strokes: $0.strokes) }
        holes = Self.normalizedHoles(trustworthyHoles, count: holeCount)

        var decodedShots = try container.decodeIfPresent([ShotRecord].self, forKey: .shots) ?? []
        for index in decodedShots.indices {
            let legacy = decodedShots[index].consumeLegacySegment()
            guard index > decodedShots.startIndex,
                  decodedShots[index - 1].hole == decodedShots[index].hole,
                  decodedShots[index - 1].distanceToNextYards == nil,
                  let distance = legacy.distance else { continue }
            decodedShots[index - 1].distanceToNextYards = distance
            decodedShots[index - 1].distanceUncertaintyYards = legacy.uncertainty
        }
        shots = decodedShots
        swings = try container.decodeIfPresent([GolfSwingMetrics].self, forKey: .swings) ?? []
        let decodedTransitions = try container.decodeIfPresent(
            [HoleTransition].self,
            forKey: .holeTransitions
        ) ?? []
        holeTransitions = Self.normalizedHoleTransitions(
            decodedTransitions,
            startedAt: startedAt,
            count: holeCount
        )
        if decodedVersion >= 4, let latestTransition = holeTransitions.last {
            currentHole = latestTransition.hole
        }
        let decodedCorrections = try container.decodeIfPresent(
            [SwingHoleCorrection].self,
            forKey: .swingHoleCorrections
        ) ?? []
        swingHoleCorrections = Self.normalizedSwingHoleCorrections(
            decodedCorrections,
            swings: swings,
            count: holeCount
        )
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        legacyScoreToPar = try container.decodeIfPresent(Int.self, forKey: .legacyScoreToPar)
        if decodedVersion < Self.currentSchemaVersion, legacyScoreToPar == nil {
            legacyScoreToPar = try container.decodeIfPresent(Int.self, forKey: .scoreToPar)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(courseName, forKey: .courseName)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(lifecycle, forKey: .lifecycle)
        try container.encode(holeCount, forKey: .holeCount)
        try container.encode(recordingDevice, forKey: .recordingDevice)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(currentHole, forKey: .currentHole)
        try container.encode(holes, forKey: .holes)
        try container.encode(holeTransitions, forKey: .holeTransitions)
        try container.encode(swingHoleCorrections, forKey: .swingHoleCorrections)
        try container.encode(shots, forKey: .shots)
        try container.encode(swings, forKey: .swings)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(legacyScoreToPar, forKey: .legacyScoreToPar)
    }

    private static func normalizedHoles(
        _ input: [HoleResult],
        count: GolfHoleCount
    ) -> [HoleResult] {
        var byNumber: [Int: HoleResult] = [:]
        for hole in input where (1...count.rawValue).contains(hole.number) {
            byNumber[hole.number] = HoleResult(
                number: hole.number,
                par: hole.par,
                strokes: hole.strokes
            )
        }
        return (1...count.rawValue).map { number in
            byNumber[number] ?? HoleResult(number: number)
        }
    }

    private static func normalizedHoleTransitions(
        _ input: [HoleTransition],
        startedAt: Date,
        count: GolfHoleCount
    ) -> [HoleTransition] {
        let ordered = input.enumerated()
            .filter {
                (1...count.rawValue).contains($0.element.hole)
                    && $0.element.transitionedAt >= startedAt
            }
            .sorted {
                if $0.element.transitionedAt == $1.element.transitionedAt {
                    if $0.element.sequence == $1.element.sequence { return $0.offset < $1.offset }
                    return $0.element.sequence < $1.element.sequence
                }
                return $0.element.transitionedAt < $1.element.transitionedAt
            }
            .map(\.element)

        var result = [HoleTransition(sequence: 1, hole: 1, transitionedAt: startedAt)]
        for transition in ordered {
            if transition.hole == 1, transition.transitionedAt == startedAt { continue }
            if result.last?.hole == transition.hole { continue }
            result.append(
                HoleTransition(
                    sequence: result.count + 1,
                    hole: transition.hole,
                    transitionedAt: transition.transitionedAt
                )
            )
        }
        return result
    }

    private static func normalizedSwingHoleCorrections(
        _ input: [SwingHoleCorrection],
        swings: [GolfSwingMetrics],
        count: GolfHoleCount
    ) -> [SwingHoleCorrection] {
        let swingIDs = Set(swings.map(\.id))
        return input.filter { correction in
            swingIDs.contains(correction.swingID)
                && correction.provenance.source == .manual
                && (correction.hole.map { (1...count.rawValue).contains($0) } ?? true)
        }
    }
}
