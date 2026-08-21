import Foundation

/// A deliberately narrow handoff to 18Birdies.
///
/// This app does not read from, write to, or authenticate with 18Birdies. The
/// generic HTTPS app link lets iOS open the official app when available while
/// remaining safe to open in a browser. The App Store URL is used only when
/// iOS rejects that primary handoff.
enum EighteenBirdiesCompanionLink {
    static let primaryURL = URL(string: "https://18birdies.app.link/xL2YVQHu4T")!
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id892700751")!

    static func fallbackURL(afterPrimaryAccepted primaryAccepted: Bool) -> URL? {
        primaryAccepted ? nil : appStoreURL
    }
}
