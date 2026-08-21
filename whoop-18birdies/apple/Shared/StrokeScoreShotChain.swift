import Foundation

// MARK: - Provenance

/// Who verified the stroke motion for the score/shot chain.
/// Watch Series 5 = live; WHOOP 5 = delayed import; hybrid = both windows.
enum StrokeMotionProvenanceKind: String, Codable, Hashable, Sendable {
    case watchLive
    case whoopDelayed
    case hybrid
    case manual
    case unknown

    var displayName: String {
        switch self {
        case .watchLive: "Apple Watch live"
        case .whoopDelayed: "WHOOP delayed"
        case .hybrid: "Watch live + WHOOP delayed"
        case .manual: "Manual"
        case .unknown: "Unknown"
        }
    }

    init(metricSource: MetricSource) {
        switch metricSource {
        case .appleWatch: self = .watchLive
        case .whoopMotion: self = .whoopDelayed
        case .manual: self = .manual
        default: self = .unknown
        }
    }
}

// MARK: - Motion summary

/// Compact motion facts for one verified stroke (not clubhead / ball flight).
struct StrokeMotionSummary: Codable, Hashable, Sendable {
    let peakG: Double
    let backswingSeconds: Double?
    let downswingSeconds: Double?
    let tempoRatio: Double?
    let heartRateBPM: Int?
    /// Mount-corrected yaw (°) when known. Positive ⇒ in-to-out.
    let correctedYawDegrees: Double?
    let pathClass: SwingPathClass
    let wrist: WatchWristMount

    init(
        peakG: Double,
        backswingSeconds: Double? = nil,
        downswingSeconds: Double? = nil,
        tempoRatio: Double? = nil,
        heartRateBPM: Int? = nil,
        correctedYawDegrees: Double? = nil,
        pathClass: SwingPathClass = .unknown,
        wrist: WatchWristMount = .golferDefault
    ) {
        self.peakG = peakG
        self.backswingSeconds = backswingSeconds
        self.downswingSeconds = downswingSeconds
        self.tempoRatio = tempoRatio
        self.heartRateBPM = heartRateBPM
        self.correctedYawDegrees = correctedYawDegrees
        self.pathClass = pathClass
        self.wrist = wrist
    }
}

// MARK: - Shot yardage

/// Yardage label for one stroke on the verified-swing chain.
///
/// Shot N yards = GPS displacement from swing N → swing N+1. The first swing
/// of a hole (or round) has no prior segment until the next swing arrives —
/// present as tee / null, never invent yards.
enum ShotYardageKind: String, Codable, Hashable, Sendable {
    /// Opening stroke of the hole/round — no prior GPS pair yet.
    case tee
    /// Measured straight-line GPS displacement to the next verified swing.
    case measured
    /// Newest swing; waiting on the next verified swing.
    case pending
    /// GPS present but withheld (hole boundary / quality).
    case withheld
    /// No usable GPS pair.
    case unavailable
}

struct ShotYardage: Codable, Hashable, Sendable {
    let kind: ShotYardageKind
    /// Rounded yards when `kind == .measured`; otherwise nil (honest empty).
    let yards: Int?
    let uncertaintyYards: Double?
    let distanceStatus: SwingShotDistanceStatus?
    let exclusionReason: SwingShotIntervalExclusionReason?
    /// Short UI token: `"tee"`, `"187 yd"`, `"pending"`, …
    let displayLabel: String

    static func tee() -> ShotYardage {
        ShotYardage(
            kind: .tee,
            yards: nil,
            uncertaintyYards: nil,
            distanceStatus: nil,
            exclusionReason: nil,
            displayLabel: "tee"
        )
    }

    static func pending() -> ShotYardage {
        ShotYardage(
            kind: .pending,
            yards: nil,
            uncertaintyYards: nil,
            distanceStatus: nil,
            exclusionReason: nil,
            displayLabel: "pending"
        )
    }

    static func from(interval: SwingShotInterval?) -> ShotYardage {
        guard let interval else { return .pending() }
        if let exclusion = interval.exclusionReason {
            return ShotYardage(
                kind: .withheld,
                yards: nil,
                uncertaintyYards: interval.distanceUncertaintyYards,
                distanceStatus: interval.distanceStatus,
                exclusionReason: exclusion,
                displayLabel: "withheld"
            )
        }
        guard interval.distanceStatus == .measured,
              let yards = interval.straightLineDisplacementYards,
              yards.isFinite, yards >= 0
        else {
            return ShotYardage(
                kind: .unavailable,
                yards: nil,
                uncertaintyYards: interval.distanceUncertaintyYards,
                distanceStatus: interval.distanceStatus,
                exclusionReason: nil,
                displayLabel: "—"
            )
        }
        let rounded = Int(yards.rounded())
        return ShotYardage(
            kind: .measured,
            yards: rounded,
            uncertaintyYards: interval.distanceUncertaintyYards,
            distanceStatus: .measured,
            exclusionReason: nil,
            displayLabel: "\(rounded) yd"
        )
    }
}

// MARK: - Verified swing

/// One verified stroke event: time, GPS, motion, provenance, path score.
struct VerifiedSwing: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let sequence: Int
    let hole: Int?
    let capturedAt: Date
    let location: SwingLocationObservation?
    let motion: StrokeMotionSummary
    let motionProvenance: StrokeMotionProvenanceKind
    let dataProvenance: DataProvenance
    /// Body-relative path score (0…100) + explanation from trail-right (default).
    let pathScore: SwingPathStrokeScore
    /// Coaching packet (cue / drill / miss) for phone journal + Watch IMPROVE.
    let coaching: SwingStrokeScore
    let club: String?
    /// Yards for *this* stroke (to the next verified swing), or tee/pending.
    let shotYardage: ShotYardage

    var score: Int? { pathScore.score }
    var explanation: String { pathScore.explanation }
}

// MARK: - Round journal

/// One journal row for phone stroke list / Watch summary.
struct StrokeJournalEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let sequence: Int
    let hole: Int?
    let capturedAt: Date
    let score: Int?
    let explanation: String
    let pathLabel: String
    let yards: Int?
    let yardageLabel: String
    let club: String?
    let motionProvenance: StrokeMotionProvenanceKind
    let scoreHeadline: String
    let missAdvice: String

    init(from swing: VerifiedSwing) {
        id = swing.id
        sequence = swing.sequence
        hole = swing.hole
        capturedAt = swing.capturedAt
        score = swing.score
        explanation = swing.explanation
        pathLabel = swing.pathScore.pathClass == .unknown
            ? SwingPathGuidance.coachingLabel(.unknown)
            : SwingPathGuidance.coachingLabel(swing.pathScore.pathClass)
        yards = swing.shotYardage.yards
        yardageLabel = swing.shotYardage.displayLabel
        club = swing.club
        motionProvenance = swing.motionProvenance
        scoreHeadline = swing.coaching.scoreHeadline
        missAdvice = swing.coaching.missAdvice
    }
}

/// Aggregated stroke journal for one round — phone UI + Watch summary sync.
struct RoundStrokeJournal: Codable, Identifiable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let roundID: UUID
    let courseName: String
    let startedAt: Date
    let wrist: WatchWristMount
    let entries: [StrokeJournalEntry]
    let verifiedSwings: [VerifiedSwing]

    var id: UUID { roundID }

    var strokeCount: Int { entries.count }

    var meanPathScore: Double? {
        let scores = entries.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    var measuredShotYards: [Int] {
        entries.compactMap(\.yards)
    }

    /// Compact Watch / phone strip for the latest stroke.
    var latestSummaryLine: String? {
        guard let last = entries.last else { return nil }
        if let score = last.score {
            return "#\(last.sequence) · \(last.pathLabel) · \(score) · \(last.yardageLabel)"
        }
        return "#\(last.sequence) · \(last.pathLabel) · \(last.yardageLabel)"
    }
}

/// Watch-facing summary of the stroke chain (WCSession application context).
struct WatchStrokeChainSummary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var roundID: UUID?
    var strokeCount: Int
    var lastPathScore: Int?
    var lastPathLabel: String?
    var lastExplanation: String?
    var lastShotYards: Int?
    var lastYardageLabel: String?
    var meanPathScore: Int?

    init(
        roundID: UUID? = nil,
        strokeCount: Int = 0,
        lastPathScore: Int? = nil,
        lastPathLabel: String? = nil,
        lastExplanation: String? = nil,
        lastShotYards: Int? = nil,
        lastYardageLabel: String? = nil,
        meanPathScore: Int? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.roundID = roundID
        self.strokeCount = strokeCount
        self.lastPathScore = lastPathScore
        self.lastPathLabel = lastPathLabel
        self.lastExplanation = lastExplanation
        self.lastShotYards = lastShotYards
        self.lastYardageLabel = lastYardageLabel
        self.meanPathScore = meanPathScore
    }

    static func from(journal: RoundStrokeJournal) -> WatchStrokeChainSummary {
        let last = journal.entries.last
        return WatchStrokeChainSummary(
            roundID: journal.roundID,
            strokeCount: journal.strokeCount,
            lastPathScore: last?.score,
            lastPathLabel: last?.pathLabel,
            lastExplanation: last?.explanation,
            lastShotYards: last?.yards,
            lastYardageLabel: last?.yardageLabel,
            meanPathScore: journal.meanPathScore.map { Int($0.rounded()) }
        )
    }
}

enum WatchStrokeChainSummaryCodec {
    static let applicationContextKey = "com.alex.whoopgolf.stroke-chain"

    static func encode(_ summary: WatchStrokeChainSummary) throws -> [String: Any] {
        let encoder = JSONEncoder()
        return [applicationContextKey: try encoder.encode(summary)]
    }

    static func decode(_ applicationContext: [String: Any]) throws -> WatchStrokeChainSummary? {
        guard let rawValue = applicationContext[applicationContextKey] else { return nil }
        guard let data = rawValue as? Data else { return nil }
        return try JSONDecoder().decode(WatchStrokeChainSummary.self, from: data)
    }

    static func merge(
        _ summary: WatchStrokeChainSummary,
        into context: [String: Any]
    ) throws -> [String: Any] {
        var merged = context
        for (key, value) in try encode(summary) {
            merged[key] = value
        }
        return merged
    }
}

// MARK: - Club hints (optional)

/// Optional club string for a journal row. Never invents club from sensors.
enum StrokeClubHint {
    static func normalize(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.utf8.count <= 32
        else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Chain builder

/// Core domain: verified swings → path score + shot yardage → round journal.
///
/// Consumes `SwingPathGuidance` (body-relative score), `GolfImprover` (coaching),
/// and `SwingShotIntervalCalculator` / `ShotDistanceCalculator` (GPS yards).
enum StrokeScoreShotChain {
    static let algorithmVersion = "stroke-score-shot-chain-v1"

    /// Optional per-swing inputs when Watch path yaw is not yet on `GolfSwingMetrics`.
    struct PathHint: Hashable, Sendable {
        /// Device (raw) downswing yaw before mount correction — preferred.
        var rawDownswingYawDegrees: Double?
        /// Already mount-corrected yaw (Watch `path_yaw_deg`).
        var correctedYawDegrees: Double?
        var pathClass: SwingPathClass?
        /// Optional WHOOP delayed raw yaw for the same window.
        var whoopRawDownswingYawDegrees: Double?
        var whoopWrist: WatchWristMount
        var club: String?

        init(
            rawDownswingYawDegrees: Double? = nil,
            correctedYawDegrees: Double? = nil,
            pathClass: SwingPathClass? = nil,
            whoopRawDownswingYawDegrees: Double? = nil,
            whoopWrist: WatchWristMount = .leadLeft,
            club: String? = nil
        ) {
            self.rawDownswingYawDegrees = rawDownswingYawDegrees
            self.correctedYawDegrees = correctedYawDegrees
            self.pathClass = pathClass
            self.whoopRawDownswingYawDegrees = whoopRawDownswingYawDegrees
            self.whoopWrist = whoopWrist
            self.club = club
        }
    }

    /// Builds the journal for a round. Intervals should already be finalized
    /// (`SwingShotIntervalCalculator.finalizingIntervals`); if not, this call
    /// finalizes them first.
    static func buildJournal(
        roundID: UUID,
        courseName: String,
        startedAt: Date,
        swings: [GolfSwingMetrics],
        holeForSwing: (GolfSwingMetrics) -> Int? = { _ in nil },
        pathHints: [UUID: PathHint] = [:],
        clubs: [UUID: String] = [:],
        wrist: WatchWristMount = .golferDefault,
        firstStrokeIsTee: Bool = true
    ) -> RoundStrokeJournal {
        let finalized = SwingShotIntervalCalculator.finalizingIntervals(in: swings)
        let ordered = finalized.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.capturedAt < $1.capturedAt
        }

        var verified: [VerifiedSwing] = []
        verified.reserveCapacity(ordered.count)

        for (index, swing) in ordered.enumerated() {
            let hint = pathHints[swing.id] ?? PathHint(
                correctedYawDegrees: swing.pathYawDegrees,
                pathClass: swing.resolvedPathClass == .unknown ? nil : swing.resolvedPathClass
            )
            let club = StrokeClubHint.normalize(clubs[swing.id] ?? hint.club)
            let isFirst = index == 0
            let isLast = index == ordered.count - 1
            // Shot N yards come from the interval finalized by swing N+1.
            // First swing with no interval yet → "tee" (null yards). Last swing
            // with no interval → pending. Measured intervals win over tee.
            let shotYardage: ShotYardage
            if let interval = swing.shotInterval {
                shotYardage = ShotYardage.from(interval: interval)
            } else if isLast {
                shotYardage = (isFirst && firstStrokeIsTee) ? .tee() : .pending()
            } else if isFirst && firstStrokeIsTee {
                shotYardage = .tee()
            } else {
                shotYardage = .pending()
            }

            verified.append(
                verify(
                    swing: swing,
                    sequence: index + 1,
                    hole: holeForSwing(swing),
                    hint: hint,
                    club: club,
                    wrist: wrist,
                    shotYardage: shotYardage
                )
            )
        }

        let entries = verified.map(StrokeJournalEntry.init(from:))
        return RoundStrokeJournal(
            schemaVersion: RoundStrokeJournal.currentSchemaVersion,
            roundID: roundID,
            courseName: courseName,
            startedAt: startedAt,
            wrist: wrist,
            entries: entries,
            verifiedSwings: verified
        )
    }

    /// Convenience over a persisted `GolfRound`.
    static func buildJournal(
        from round: GolfRound,
        pathHints: [UUID: PathHint] = [:],
        clubs: [UUID: String] = [:],
        wrist: WatchWristMount = .golferDefault
    ) -> RoundStrokeJournal {
        buildJournal(
            roundID: round.id,
            courseName: round.courseName,
            startedAt: round.startedAt,
            swings: round.swings,
            holeForSwing: { swing in
                round.holeAssignment(for: swing.id)?.hole
            },
            pathHints: pathHints,
            clubs: clubs,
            wrist: wrist
        )
    }

    static func watchSummary(from journal: RoundStrokeJournal) -> WatchStrokeChainSummary {
        .from(journal: journal)
    }

    /// Enriches a live face with the latest path score for Watch summary sync.
    static func enrichLiveFace(
        _ face: WatchLiveFace,
        journal: RoundStrokeJournal
    ) -> WatchLiveFace {
        var enriched = face
        if let last = journal.entries.last {
            if enriched.lastShotYards == nil {
                enriched.lastShotYards = last.yards
            }
            enriched.lastPathScore = last.score
            enriched.lastPathLabel = last.pathLabel
        }
        enriched.strokeCount = journal.strokeCount
        if enriched.courseName == nil || enriched.courseName?.isEmpty == true {
            enriched.courseName = journal.courseName
        }
        enriched.wristMount = journal.wrist
        return enriched
    }

    /// Persist path score + explanation + tip onto each `GolfSwingMetrics` row
    /// while keeping shot intervals (swing-to-swing yards) intact.
    static func enrichSwingMetrics(
        _ swings: [GolfSwingMetrics],
        pathHints: [UUID: PathHint] = [:],
        wrist: WatchWristMount = .golferDefault
    ) -> [GolfSwingMetrics] {
        let ordered = swings.sorted { $0.capturedAt < $1.capturedAt }
        guard !ordered.isEmpty else { return swings }

        let journal = buildJournal(
            roundID: UUID(),
            courseName: "live",
            startedAt: ordered.first?.capturedAt ?? Date(),
            swings: ordered,
            holeForSwing: { _ in nil },
            pathHints: pathHints,
            clubs: [:],
            wrist: wrist
        )

        let byID = Dictionary(uniqueKeysWithValues: journal.verifiedSwings.map { ($0.id, $0) })
        return ordered.map { swing in
            guard let verified = byID[swing.id] else { return swing }
            return swing.withStrokeCoaching(
                pathScore: verified.score,
                pathExplanation: verified.explanation,
                improverTip: verified.coaching.tip.postSwing,
                pathClass: verified.motion.pathClass.rawValue,
                pathYawDegrees: verified.motion.correctedYawDegrees ?? swing.pathYawDegrees
            )
        }
    }

    // MARK: - Verify one stroke

    static func verify(
        swing: GolfSwingMetrics,
        sequence: Int,
        hole: Int?,
        hint: PathHint,
        club: String?,
        wrist: WatchWristMount,
        shotYardage: ShotYardage
    ) -> VerifiedSwing {
        let scored = scorePath(
            swing: swing,
            hint: hint,
            wrist: wrist
        )
        let coaching = GolfImprover.strokeScore(
            path: scored.pathClass,
            correctedYawDegrees: scored.correctedYawDegrees,
            tempoRatio: swing.tempoRatio ?? scored.tempoRatio,
            wrist: wrist,
            id: swing.id
        )
        let motionKind: StrokeMotionProvenanceKind
        if hint.whoopRawDownswingYawDegrees != nil,
           swing.provenance.source == .appleWatch || hint.rawDownswingYawDegrees != nil {
            motionKind = .hybrid
        } else {
            motionKind = StrokeMotionProvenanceKind(metricSource: swing.provenance.source)
        }

        let motion = StrokeMotionSummary(
            peakG: swing.peakG,
            backswingSeconds: swing.backswingSeconds,
            downswingSeconds: swing.downswingSeconds,
            tempoRatio: swing.tempoRatio,
            heartRateBPM: swing.heartRateBPM,
            correctedYawDegrees: scored.correctedYawDegrees,
            pathClass: scored.pathClass,
            wrist: wrist
        )

        return VerifiedSwing(
            id: swing.id,
            sequence: sequence,
            hole: hole,
            capturedAt: swing.capturedAt,
            location: swing.location,
            motion: motion,
            motionProvenance: motionKind,
            dataProvenance: swing.provenance,
            pathScore: scored,
            coaching: coaching,
            club: club,
            shotYardage: shotYardage
        )
    }

    private static func scorePath(
        swing: GolfSwingMetrics,
        hint: PathHint,
        wrist: WatchWristMount
    ) -> SwingPathStrokeScore {
        if let raw = hint.rawDownswingYawDegrees, raw.isFinite {
            var live = SwingPathGuidance.scoreStroke(
                downswingYawDegrees: raw,
                tempoRatio: swing.tempoRatio,
                wrist: wrist
            )
            if let whoopRaw = hint.whoopRawDownswingYawDegrees {
                live = SwingPathGuidance.refineWithWhoop(
                    live: live,
                    whoopDownswingYawDegrees: whoopRaw,
                    whoopWrist: hint.whoopWrist
                )
            }
            return live
        }

        // Stored Watch path_yaw_deg is already mount-corrected — do not
        // re-apply pathSign via scoreStroke.
        let corrected = hint.correctedYawDegrees ?? swing.pathYawDegrees
        let path = hint.pathClass
            ?? (swing.resolvedPathClass != .unknown ? swing.resolvedPathClass : nil)
            ?? classifyFromCorrected(corrected)

        let improver = GolfImprover.strokeScore(
            path: path,
            correctedYawDegrees: corrected,
            tempoRatio: swing.tempoRatio,
            wrist: wrist,
            id: swing.id
        )

        var scored = SwingPathStrokeScore(
            score: improver.pathScore,
            pathClass: path,
            correctedYawDegrees: corrected,
            explanation: improver.explanation,
            wrist: wrist,
            scorer: .watchLive,
            tempoRatio: swing.tempoRatio
        )

        if let whoopRaw = hint.whoopRawDownswingYawDegrees,
           let correctedYaw = corrected,
           wrist.pathSign != 0 {
            // Invert mount correction so refineWithWhoop can re-apply Watch sign.
            let syntheticRaw = correctedYaw / wrist.pathSign
            let live = SwingPathGuidance.scoreStroke(
                downswingYawDegrees: syntheticRaw,
                tempoRatio: swing.tempoRatio,
                wrist: wrist
            )
            scored = SwingPathGuidance.refineWithWhoop(
                live: live,
                whoopDownswingYawDegrees: whoopRaw,
                whoopWrist: hint.whoopWrist
            )
        }

        return scored
    }

    private static func classifyFromCorrected(_ corrected: Double?) -> SwingPathClass {
        guard let yaw = corrected, yaw.isFinite else { return .unknown }
        if abs(yaw) < SwingPathGuidance.onPlaneDegrees { return .onPlane }
        return yaw > 0 ? .inToOut : .outToIn
    }
}

// MARK: - Persistence

/// Protected per-round stroke journal files for phone UI + Watch sync rebuild.
actor StrokeJournalStore {
    enum StoreError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "The protected stroke journal store is unavailable."
        }
    }

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("WhoopGolf", isDirectory: true)
        let resolved = base ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("WhoopGolf", isDirectory: true)
        self.directory = resolved.appendingPathComponent("StrokeJournals", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ journal: RoundStrokeJournal) throws {
        try prepareDirectory()
        let url = directory
            .appendingPathComponent(journal.roundID.uuidString)
            .appendingPathExtension("json")
        try encoder.encode(journal).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func load(roundID: UUID) throws -> RoundStrokeJournal? {
        try prepareDirectory()
        let url = directory
            .appendingPathComponent(roundID.uuidString)
            .appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try decoder.decode(RoundStrokeJournal.self, from: data)
    }

    /// Rebuild from the round, persist, and return the journal + Watch summary.
    func refresh(
        round: GolfRound,
        pathHints: [UUID: StrokeScoreShotChain.PathHint] = [:],
        clubs: [UUID: String] = [:],
        wrist: WatchWristMount = .golferDefault
    ) throws -> (journal: RoundStrokeJournal, watchSummary: WatchStrokeChainSummary) {
        let journal = StrokeScoreShotChain.buildJournal(
            from: round,
            pathHints: pathHints,
            clubs: clubs,
            wrist: wrist
        )
        try save(journal)
        return (journal, StrokeScoreShotChain.watchSummary(from: journal))
    }

    private func prepareDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            throw StoreError.unavailable
        }
    }
}
