import Foundation

/// Where finished sessions POST when upload is enabled.
///
/// Stored in UserDefaults so you can point the watch at `wb serve` from the app
/// rather than editing Swift and rebuilding every time your Mac's address changes.
enum IngestSettings {
    static let urlKey = "ingestURL"
    static let tokenKey = "ingestToken"

    static var url: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                       forKey: urlKey) }
    }

    static var token: String {
        get { UserDefaults.standard.string(forKey: tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                        forKey: tokenKey) }
    }

    /// Whether upload will be attempted. Token may be empty when `wb serve`
    /// generated one at launch and you have not copied it yet — the server
    /// will refuse with 401, which the outbox handles.
    static var isConfigured: Bool {
        !url.isEmpty
    }
}
