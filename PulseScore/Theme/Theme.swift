import SwiftUI

/// Centralized color constants for PulseScore's dark, WHOOP/Bevel-inspired look.
/// `enum Theme` with no cases and only `static` members is a common Swift pattern for
/// a namespace — we're never going to make an *instance* of Theme, we just want
/// `Theme.background` etc. callable without importing a singleton object. (An enum
/// with zero cases can't be instantiated at all, which documents that intent.)
enum Theme {
    // MARK: Backgrounds
    static let background = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let cardBackground = Color(red: 0.11, green: 0.11, blue: 0.13)

    // MARK: Text
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.6)

    // MARK: Score bands
    static let scoreLow = Color(red: 0.95, green: 0.30, blue: 0.30)    // red
    static let scoreMedium = Color(red: 0.95, green: 0.75, blue: 0.25) // yellow
    static let scoreHigh = Color(red: 0.30, green: 0.85, blue: 0.55)   // green

    /// Maps a 0...100 score to a band color. The low/medium/high thresholds themselves
    /// live in `ScoreEngine.band(for:)`, not here — Theme is purely presentation, so it
    /// asks ScoreEngine what band a score falls in rather than duplicating the cutoffs.
    static func color(forScore score: Int) -> Color {
        switch ScoreEngine.band(for: score) {
        case .low: return scoreLow
        case .medium: return scoreMedium
        case .high: return scoreHigh
        }
    }
}
