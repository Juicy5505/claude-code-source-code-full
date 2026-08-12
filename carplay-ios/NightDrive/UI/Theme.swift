import SwiftUI

/// NightDrive palette — deliberately dark-only for glare-safe night driving.
enum Theme {
    static let ground   = Color(red: 0.039, green: 0.055, blue: 0.075)   // #0A0E13
    static let panel    = Color(red: 0.067, green: 0.094, blue: 0.137)   // #111823
    static let hairline = Color(red: 0.133, green: 0.188, blue: 0.247)   // #22303F
    static let text     = Color(red: 0.918, green: 0.949, blue: 0.976)   // #EAF2F9
    static let muted    = Color(red: 0.494, green: 0.576, blue: 0.659)   // #7E93A8
    static let accent   = Color(red: 0.271, green: 0.839, blue: 0.878)   // #45D6E0
    static let good     = Color(red: 0.290, green: 0.871, blue: 0.502)   // #4ADE80
    static let warn     = Color(red: 1.000, green: 0.706, blue: 0.329)   // #FFB454
    static let crit     = Color(red: 1.000, green: 0.384, blue: 0.349)   // #FF6259
}
