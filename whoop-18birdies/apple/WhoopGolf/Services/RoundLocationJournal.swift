import Foundation

/// A quality-gated estimate of the iPhone position at a sensor event time.
///
/// This is intentionally not described as an exact ball location. GPS accuracy,
/// sampling cadence, and the delay between impact and movement all limit what
/// can be inferred from the phone's location timeline.
struct RoundLocationCorrelation: Hashable, Sendable {
    let estimatedFix: LocationFix
    let method: SwingLocationCorrelationMethod
    let maximumSourceTimeGapSeconds: TimeInterval
}

/// Crash-tolerant, protected storage for the location timeline of one round.
///
/// Each fix is a newline-delimited JSON record. Appends are synchronized before
/// returning, and a partially written final record is ignored and removed on
/// the next load. Compaction is atomic and bounds both timeline length and file
/// size so a long-running round cannot grow without limit.
actor RoundLocationJournal {
    struct Configuration: Sendable {
        let maximumEntries: Int
        let maximumTimelineDuration: TimeInterval
        let maximumFileSizeBytes: Int
        let maximumJournalAge: TimeInterval

        init(
            maximumEntries: Int = 15_000,
            maximumTimelineDuration: TimeInterval = 24 * 60 * 60,
            maximumFileSizeBytes: Int = 8 * 1_024 * 1_024,
            maximumJournalAge: TimeInterval = 30 * 24 * 60 * 60
        ) {
            self.maximumEntries = max(1, maximumEntries)
            self.maximumTimelineDuration = max(60, maximumTimelineDuration)
            self.maximumFileSizeBytes = max(1_024, maximumFileSizeBytes)
            self.maximumJournalAge = max(60 * 60, maximumJournalAge)
        }
    }

    enum JournalError: LocalizedError {
        case invalidFix
        case roundNotStarted
        case activeRoundMismatch
        case unavailable

        var errorDescription: String? {
            switch self {
            case .invalidFix:
                "The location update was invalid and was not saved."
            case .roundNotStarted:
                "Location journaling has not started for this round."
            case .activeRoundMismatch:
                "A different round is currently using the location journal."
            case .unavailable:
                "The protected round location journal is unavailable."
            }
        }
    }

    private struct Record: Codable, Sendable {
        let schemaVersion: Int
        let fix: LocationFix

        init(fix: LocationFix) {
            self.schemaVersion = 1
            self.fix = fix
        }
    }

    private struct ReadResult {
        var fixes: [LocationFix]
        var hadCorruption: Bool
        var wasPruned: Bool
    }

    private let directory: URL
    private let configuration: Configuration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var activeRoundID: UUID?
    private var entryCountByRound: [UUID: Int] = [:]
    private var oldestTimestampByRound: [UUID: Date] = [:]
    private var newestTimestampByRound: [UUID: Date] = [:]

    init(directory: URL? = nil, configuration: Configuration = Configuration()) {
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            let base = applicationSupport ?? FileManager.default.temporaryDirectory
            self.directory = base
                .appendingPathComponent("WhoopGolf", isDirectory: true)
                .appendingPathComponent("RoundLocationJournals", isDirectory: true)
        }
        self.configuration = configuration

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    /// Opens an existing journal without truncating it, or creates a new one.
    /// Calling this after process relaunch resumes the same round timeline.
    func start(roundID: UUID) throws {
        if let activeRoundID, activeRoundID != roundID {
            throw JournalError.activeRoundMismatch
        }

        try prepareDirectory()
        _ = try purgeExpired(referenceDate: .now, preserving: roundID)
        try prepareFile(for: roundID)
        let result = try readAndRetain(roundID: roundID)
        if result.hadCorruption || result.wasPruned || needsCompaction(result.fixes, roundID: roundID) {
            try rewrite(result.fixes, roundID: roundID)
        } else {
            updateBounds(result.fixes, roundID: roundID)
        }
        activeRoundID = roundID
    }

    /// Appends one callback observation and synchronizes it to protected storage.
    func append(_ fix: LocationFix, roundID: UUID) throws {
        guard activeRoundID != nil else { throw JournalError.roundNotStarted }
        guard activeRoundID == roundID else { throw JournalError.activeRoundMismatch }
        guard Self.isValid(fix) else { throw JournalError.invalidFix }

        try prepareDirectory()
        let url = try prepareFile(for: roundID)
        var data = try encoder.encode(Record(fix: fix))
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        entryCountByRound[roundID, default: 0] += 1
        oldestTimestampByRound[roundID] = min(
            oldestTimestampByRound[roundID] ?? fix.capturedAt,
            fix.capturedAt
        )
        newestTimestampByRound[roundID] = max(
            newestTimestampByRound[roundID] ?? fix.capturedAt,
            fix.capturedAt
        )

        let fileSize = try fileSize(at: url)
        let oldest = oldestTimestampByRound[roundID] ?? fix.capturedAt
        let newest = newestTimestampByRound[roundID] ?? fix.capturedAt
        let exceedsDuration = newest.timeIntervalSince(oldest) > configuration.maximumTimelineDuration
        if entryCountByRound[roundID, default: 0] > configuration.maximumEntries ||
            fileSize > configuration.maximumFileSizeBytes ||
            exceedsDuration {
            let retained = try readAndRetain(roundID: roundID).fixes
            try rewrite(retained, roundID: roundID)
        }
    }

    /// Flushes and closes the logical recording session. Each append is already
    /// synchronized, so this does not need a separate buffered write.
    func stop(roundID: UUID) throws {
        guard activeRoundID != nil else { return }
        guard activeRoundID == roundID else { throw JournalError.activeRoundMismatch }
        activeRoundID = nil
    }

    /// Loads all retained, valid observations in observed-time order.
    func load(roundID: UUID) throws -> [LocationFix] {
        try prepareDirectory()
        _ = try purgeExpired(referenceDate: .now, preserving: activeRoundID)
        guard FileManager.default.fileExists(atPath: fileURL(for: roundID).path) else {
            return []
        }
        let result = try readAndRetain(roundID: roundID)
        if result.hadCorruption || result.wasPruned || needsCompaction(result.fixes, roundID: roundID) {
            try rewrite(result.fixes, roundID: roundID)
        } else {
            updateBounds(result.fixes, roundID: roundID)
        }
        return result.fixes
    }

    /// Removes inactive raw GPS timelines after a bounded correlation window.
    /// Finished round summaries remain in `RoundFileStore`; only the raw,
    /// high-frequency journal is deleted. The currently active round is never
    /// removed, even when a device clock or file timestamp is unusual.
    @discardableResult
    func purgeExpired(
        referenceDate: Date = .now,
        preserving roundIDToPreserve: UUID? = nil
    ) throws -> Int {
        try prepareDirectory()
        let preserved = roundIDToPreserve ?? activeRoundID
        let cutoff = referenceDate.addingTimeInterval(-configuration.maximumJournalAge)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var removed = 0
        for file in files where file.pathExtension.lowercased() == "ndjson" {
            guard file.deletingPathExtension().lastPathComponent.lowercased()
                    != preserved?.uuidString.lowercased() else { continue }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff else { continue }
            try FileManager.default.removeItem(at: file)
            if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) {
                entryCountByRound[id] = nil
                oldestTimestampByRound[id] = nil
                newestTimestampByRound[id] = nil
            }
            removed += 1
        }
        return removed
    }

    /// Explicitly deletes a finished round's raw GPS timeline. Callers must
    /// keep the durable round summary and imported swing locations separately.
    func delete(roundID: UUID) throws {
        guard activeRoundID != roundID else { throw JournalError.activeRoundMismatch }
        let url = fileURL(for: roundID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        entryCountByRound[roundID] = nil
        oldestTimestampByRound[roundID] = nil
        newestTimestampByRound[roundID] = nil
    }

    /// Finds a quality-gated position estimate for a delayed WHOOP swing time.
    /// Interpolation is preferred when two accepted fixes bracket the event;
    /// otherwise the nearest accepted fix is used within `maximumTimeGap`.
    func correlate(
        roundID: UUID,
        at timestamp: Date,
        maximumTimeGap: TimeInterval = 15,
        maximumHorizontalAccuracy: Double = 25
    ) throws -> RoundLocationCorrelation? {
        guard maximumTimeGap.isFinite, maximumTimeGap >= 0,
              maximumHorizontalAccuracy.isFinite, maximumHorizontalAccuracy >= 0
        else { return nil }

        let eligible = try load(roundID: roundID).filter {
            $0.horizontalAccuracyMeters <= maximumHorizontalAccuracy
        }
        guard !eligible.isEmpty else { return nil }

        if let exact = eligible.first(where: { $0.capturedAt == timestamp }) {
            return RoundLocationCorrelation(
                estimatedFix: exact,
                method: .nearestTimelineFix,
                maximumSourceTimeGapSeconds: 0
            )
        }

        let before = eligible.last(where: { $0.capturedAt < timestamp })
        let after = eligible.first(where: { $0.capturedAt > timestamp })

        if let before, let after {
            let beforeGap = timestamp.timeIntervalSince(before.capturedAt)
            let afterGap = after.capturedAt.timeIntervalSince(timestamp)
            if beforeGap <= maximumTimeGap, afterGap <= maximumTimeGap {
                let total = after.capturedAt.timeIntervalSince(before.capturedAt)
                if total > 0 {
                    let progress = beforeGap / total
                    let altitude: Double?
                    if let beforeAltitude = before.altitudeMeters,
                       let afterAltitude = after.altitudeMeters {
                        altitude = beforeAltitude + ((afterAltitude - beforeAltitude) * progress)
                    } else {
                        altitude = nil
                    }
                    let accuracy = max(
                        before.horizontalAccuracyMeters,
                        after.horizontalAccuracyMeters
                    )
                    let estimate = LocationFix(
                        latitude: before.latitude + ((after.latitude - before.latitude) * progress),
                        longitude: before.longitude + ((after.longitude - before.longitude) * progress),
                        altitudeMeters: altitude,
                        horizontalAccuracyMeters: accuracy,
                        capturedAt: timestamp,
                        provenance: DataProvenance(
                            source: .derived,
                            observedAt: timestamp,
                            quality: .estimated,
                            algorithmVersion: "iphone-gps-timeline-linear-v1",
                            inputSources: [.iphoneGPS]
                        )
                    )
                    return RoundLocationCorrelation(
                        estimatedFix: estimate,
                        method: .interpolatedTimelineFix,
                        maximumSourceTimeGapSeconds: max(beforeGap, afterGap)
                    )
                }
            }
        }

        let nearest = eligible.min {
            abs($0.capturedAt.timeIntervalSince(timestamp)) <
                abs($1.capturedAt.timeIntervalSince(timestamp))
        }
        guard let nearest else { return nil }
        let gap = abs(nearest.capturedAt.timeIntervalSince(timestamp))
        guard gap <= maximumTimeGap else { return nil }
        return RoundLocationCorrelation(
            estimatedFix: nearest,
            method: .nearestTimelineFix,
            maximumSourceTimeGapSeconds: gap
        )
    }

    private static func isValid(_ fix: LocationFix) -> Bool {
        let timestamp = fix.capturedAt.timeIntervalSince1970
        return fix.latitude.isFinite && fix.longitude.isFinite &&
            (-90...90).contains(fix.latitude) && (-180...180).contains(fix.longitude) &&
            fix.horizontalAccuracyMeters.isFinite &&
            fix.horizontalAccuracyMeters >= 0 && fix.horizontalAccuracyMeters <= 10_000 &&
            timestamp.isFinite && timestamp >= 0 &&
            fix.capturedAt <= Date().addingTimeInterval(5 * 60) &&
            (fix.altitudeMeters?.isFinite ?? true) &&
            fix.provenance.source == .iphoneGPS &&
            fix.provenance.observedAt == fix.capturedAt
    }

    private func fileURL(for roundID: UUID) -> URL {
        directory
            .appendingPathComponent(roundID.uuidString.lowercased())
            .appendingPathExtension("ndjson")
    }

    @discardableResult
    private func prepareFile(for roundID: UUID) throws -> URL {
        var url = fileURL(for: roundID)
        if !FileManager.default.fileExists(atPath: url.path) {
            let created = FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
            guard created else { throw JournalError.unavailable }
        } else {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
    }

    private func readAndRetain(roundID: UUID) throws -> ReadResult {
        let data = try Data(contentsOf: fileURL(for: roundID), options: [.mappedIfSafe])
        var fixes: [LocationFix] = []
        var hadCorruption = false
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            do {
                let record = try decoder.decode(Record.self, from: Data(line))
                guard record.schemaVersion == 1, Self.isValid(record.fix) else {
                    hadCorruption = true
                    continue
                }
                fixes.append(record.fix)
            } catch {
                hadCorruption = true
            }
        }
        fixes.sort { $0.capturedAt < $1.capturedAt }
        let retainedFixes = retained(fixes)
        return ReadResult(
            fixes: retainedFixes,
            hadCorruption: hadCorruption,
            wasPruned: retainedFixes.count != fixes.count
        )
    }

    private func retained(_ fixes: [LocationFix]) -> [LocationFix] {
        guard let newest = fixes.last else { return [] }
        let cutoff = newest.capturedAt.addingTimeInterval(-configuration.maximumTimelineDuration)
        var result = Array(fixes.filter { $0.capturedAt >= cutoff }.suffix(configuration.maximumEntries))

        var encodedSize = encodedJournalSize(result)
        while result.count > 1, encodedSize > configuration.maximumFileSizeBytes {
            result.removeFirst()
            encodedSize = encodedJournalSize(result)
        }
        return result
    }

    private func encodedJournalSize(_ fixes: [LocationFix]) -> Int {
        fixes.reduce(into: 0) { size, fix in
            size += ((try? encoder.encode(Record(fix: fix)).count) ?? 0) + 1
        }
    }

    private func needsCompaction(_ fixes: [LocationFix], roundID: UUID) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL(for: roundID).path
        ), let size = attributes[.size] as? NSNumber else {
            return false
        }
        return fixes.count > configuration.maximumEntries ||
            size.intValue > configuration.maximumFileSizeBytes
    }

    private func rewrite(_ fixes: [LocationFix], roundID: UUID) throws {
        let retained = retained(fixes)
        var data = Data()
        for fix in retained {
            data.append(try encoder.encode(Record(fix: fix)))
            data.append(0x0A)
        }
        try data.write(
            to: fileURL(for: roundID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL(for: roundID).path
        )
        updateBounds(retained, roundID: roundID)
    }

    private func updateBounds(_ fixes: [LocationFix], roundID: UUID) {
        entryCountByRound[roundID] = fixes.count
        oldestTimestampByRound[roundID] = fixes.first?.capturedAt
        newestTimestampByRound[roundID] = fixes.last?.capturedAt
    }

    private func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
