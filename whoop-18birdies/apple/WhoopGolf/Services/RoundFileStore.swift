import Foundation

actor RoundFileStore {
    struct Snapshot: Sendable {
        let activeDraft: GolfRound?
        let additionalDraftCount: Int
        let finishedRounds: [GolfRound]
    }

    enum StoreError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "The protected round store is unavailable."
        }
    }

    private let directory: URL
    private let quarantineDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("WhoopGolf", isDirectory: true)
        let resolved = base ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("WhoopGolf", isDirectory: true)
        self.directory = resolved.appendingPathComponent("Rounds", isDirectory: true)
        self.quarantineDirectory = resolved.appendingPathComponent("Quarantine", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ round: GolfRound) throws {
        try prepareDirectory(directory)
        let url = directory.appendingPathComponent(round.id.uuidString).appendingPathExtension("json")
        try encoder.encode(round).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Returns the one resumable draft and finished history separately. Older
    /// drafts are preserved on disk but never leak into trends/history.
    func snapshot() throws -> Snapshot {
        let all = try loadAll()
        let drafts = all
            .filter { !$0.isFinished }
            .sorted { $0.startedAt > $1.startedAt }
        let finished = all
            .filter(\.isFinished)
            .sorted { $0.startedAt > $1.startedAt }
        return Snapshot(
            activeDraft: drafts.first,
            additionalDraftCount: max(0, drafts.count - 1),
            finishedRounds: finished
        )
    }

    /// Integration consumers (including the Watch importer) need both drafts
    /// and finished rounds so an active round can receive linked sensor data.
    func rounds() throws -> [GolfRound] {
        try loadAll().sorted { $0.startedAt > $1.startedAt }
    }

    /// UI history and analytics intentionally receive only finalized rounds.
    func finishedRounds() throws -> [GolfRound] {
        try snapshot().finishedRounds
    }

    private func loadAll() throws -> [GolfRound] {
        try prepareDirectory(directory)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }

        var result: [GolfRound] = []
        for url in urls {
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                result.append(try decoder.decode(GolfRound.self, from: data))
            } catch {
                try quarantine(url)
            }
        }
        return result
    }

    private func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func quarantine(_ source: URL) throws {
        try prepareDirectory(quarantineDirectory)
        let destination = quarantineDirectory
            .appendingPathComponent(
                source.deletingPathExtension().lastPathComponent + "-corrupt-\(UUID().uuidString)"
            )
            .appendingPathExtension("json")
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
