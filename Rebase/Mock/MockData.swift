import Foundation

/// Deterministic 14-day sample dataset, plus scores computed from it via the real
/// `ScoreEngine` — nothing about *scoring* is faked here anymore, only the underlying
/// activity numbers are. This lets the whole UI (ring, cards, trend chart) run against
/// realistic, ScoreEngine-produced output before HealthKit exists (that's step 3).
///
/// 14 days is intentional, not arbitrary: computing a genuine trailing 7-day score for
/// each of the last 7 days requires a full 7-day baseline behind *each* of those days
/// too — 7 (the trend) + 7 (baseline for the oldest trend day) = 14. This mirrors
/// exactly what HealthKitManager will later fetch from real Health data.
enum MockData {

    /// Day-by-day activity, oldest (index 0, 13 days ago) to newest (index 13, today).
    /// Hand-picked rather than randomized so runs/tests/previews stay reproducible.
    static let fourteenDayHistory: [DailyMetrics] = {
        // (activeEnergy cal, exerciseMinutes, steps, restingHeartRate bpm)
        let raw: [(Double, Double, Double, Double)] = [
            (320, 22, 6200, 63),
            (340, 24, 6800, 62),
            (300, 18, 5800, 63),
            (450, 38, 9200, 60),
            (500, 42, 10500, 59),
            (280, 15, 5200, 64),
            (400, 30, 8000, 61),
            (600, 55, 12000, 57),
            (250, 12, 4500, 65),
            (380, 28, 7800, 61),
            (420, 33, 8600, 60),
            (470, 40, 9800, 59),
            (300, 20, 6000, 63),
            (420, 28, 9800, 64) // today — RHR nudged above baseline so Workout and
                                // Recovery visibly land in different bands in the demo
        ]

        let calendar = Calendar.current
        let lastIndex = raw.count - 1
        return raw.enumerated().map { index, values in
            let daysAgo = lastIndex - index
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
            let (activeEnergy, exerciseMinutes, steps, restingHeartRate) = values
            return DailyMetrics(
                date: date,
                activeEnergy: activeEnergy,
                exerciseMinutes: exerciseMinutes,
                steps: steps,
                restingHeartRate: restingHeartRate
            )
        }
    }()

    /// Today's full score result: the last day in `fourteenDayHistory`, scored against
    /// the 7 days immediately before it. Force-unwrapped because we control this mock
    /// array and guarantee it's non-empty — `ScoreEngine.score` returning `nil` here
    /// would mean a bug in this file, not a real "no data" state to handle gracefully.
    static let todayResult: ScoreResult = {
        let history = fourteenDayHistory
        let today = history.last!
        let priorDays = Array(history.suffix(ScoreEngine.baselineWindowDays + 1).dropLast())
        return ScoreEngine.score(today: today, priorDays: priorDays)!
    }()

    /// Today's Recovery result, from the same 14-day history — a separate score, not
    /// derived from `todayResult` in any way, since Workout and Recovery are
    /// deliberately independent constructs (see ScoreEngine's doc comment).
    static let recoveryResult: ScoreResult = {
        let history = fourteenDayHistory
        let today = history.last!
        let priorDays = Array(history.suffix(ScoreEngine.baselineWindowDays + 1).dropLast())
        return ScoreEngine.recoveryScore(today: today, priorDays: priorDays)!
    }()

    /// The last 7 days' scores, each computed against its own trailing 7-day baseline —
    /// real ScoreEngine output end to end, not hand-typed numbers.
    static let trend: [ScoreHistoryPoint] = {
        let history = fourteenDayHistory
        let windowSize = ScoreEngine.baselineWindowDays
        let trendStartIndex = history.count - windowSize

        return (trendStartIndex..<history.count).map { index in
            let today = history[index]
            let priorDays = Array(history[(index - windowSize)..<index])
            let result = ScoreEngine.score(today: today, priorDays: priorDays)!
            return ScoreHistoryPoint(date: today.date, score: result.score)
        }
    }()
}
