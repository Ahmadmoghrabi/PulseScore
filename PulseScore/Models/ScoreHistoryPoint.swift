import Foundation

/// One point on the 7-day trend chart: a date and the score computed for it.
struct ScoreHistoryPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let score: Int
}
