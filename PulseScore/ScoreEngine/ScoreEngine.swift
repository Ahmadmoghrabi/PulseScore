import Foundation

/// The result of scoring one day: an overall 0...100 score plus the per-metric
/// breakdown that explains how it was computed. This struct is the entire contract
/// between ScoreEngine and everything downstream (views, mock data, tests) — nobody
/// else needs to know the formula, just this shape.
struct ScoreResult {
    let score: Int
    let breakdown: [MetricScoreBreakdown]
}

/// Pure scoring logic. Deliberately has zero dependency on HealthKit or SwiftUI —
/// `import`s only `Foundation`. That's what makes it possible to unit test with plain
/// mock data (no simulator, no permissions, no async) and to reason about or tweak the
/// formula in exactly one place.
///
/// ## The formula, in plain language
/// For each of the three *scored* metrics (active energy, exercise minutes, steps):
///   1. Compare today's value to the person's own 7-day baseline average for that metric.
///   2. Convert that into a percentage of baseline, **capped at 100%** — matching or
///      beating your own baseline earns full credit, but there's no bonus for wildly
///      overshooting it. This keeps one huge day from making three lazy ones look fine,
///      and keeps the number easy to explain: "you hit 100% of your own normal."
///   3. Multiply that capped percentage by the metric's weight.
/// Sum the three weighted contributions → the 0...100 score. Weights sum to 1.0, so a
/// day that exactly matches baseline on everything scores exactly 100.
///
/// Resting heart rate is scored *separately*, as its own Recovery score (see
/// `recoveryScore`), rather than folded into the Workout Score above — mixing an
/// "effort" signal with a "physiological state" signal into one formula would make
/// the number harder to explain, and explainability is the whole point here.
enum ScoreEngine {

    // MARK: Weights — must sum to 1.0

    /// Largest weight: the most direct signal of "how much work did the body do today,"
    /// and present for essentially every user/device combination.
    static let activeEnergyWeight = 0.40
    /// Close second: reflects intentional effort, not just incidental movement.
    static let exerciseMinutesWeight = 0.35
    /// Smallest of the three: a lot of step count is incidental (errands, walking
    /// around) rather than deliberate exercise.
    static let stepsWeight = 0.25

    /// How many prior days should feed the rolling baseline. Callers (HealthKitManager,
    /// mock data, tests) are expected to supply this many days — ScoreEngine itself just
    /// averages whatever it's handed, so it doesn't need to know about calendars at all.
    static let baselineWindowDays = 7

    /// Computes today's score against a baseline built from `priorDays`.
    ///
    /// - Parameters:
    ///   - today: today's metrics.
    ///   - priorDays: the days to average into the baseline — normally the
    ///     `baselineWindowDays` days immediately before today, NOT including today.
    /// - Returns: `nil` if `priorDays` is empty, since there's no baseline to compare
    ///   against yet (e.g. a brand-new user). The UI is expected to show a
    ///   "not enough data yet" state in that case rather than a misleading score.
    static func score(today: DailyMetrics, priorDays: [DailyMetrics]) -> ScoreResult? {
        guard !priorDays.isEmpty else { return nil }

        let activeEnergyBreakdown = breakdown(
            metricName: "Active Energy",
            today: today.activeEnergy,
            baseline: average(priorDays.map(\.activeEnergy)),
            unit: "cal"
        )
        let exerciseBreakdown = breakdown(
            metricName: "Exercise Minutes",
            today: today.exerciseMinutes,
            baseline: average(priorDays.map(\.exerciseMinutes)),
            unit: "min"
        )
        let stepsBreakdown = breakdown(
            metricName: "Steps",
            today: today.steps,
            baseline: average(priorDays.map(\.steps)),
            unit: "steps"
        )

        let weightedTotal =
            activeEnergyBreakdown.contributionPercent * activeEnergyWeight +
            exerciseBreakdown.contributionPercent * exerciseMinutesWeight +
            stepsBreakdown.contributionPercent * stepsWeight

        let allBreakdowns = [activeEnergyBreakdown, exerciseBreakdown, stepsBreakdown]

        return ScoreResult(score: Int(weightedTotal.rounded()), breakdown: allBreakdowns)
    }

    // MARK: - Recovery score

    /// How many bpm above baseline counts as "zero recovery" — an intentionally simple
    /// linear scale, not a physiologically validated model. Real recovery scores
    /// (WHOOP, Oura, etc.) blend heart rate variability, sleep, and more signals; this
    /// project trades that sophistication for a formula that fits in one sentence.
    static let recoveryMaxElevationBpm = 10.0

    /// Scores "recovery" from resting heart rate alone, completely separately from the
    /// Workout Score above — they're different constructs (effort vs. physiological
    /// state) and deliberately never combined into one number.
    ///
    /// At or below your own 7-day baseline RHR scores 100 (full credit — your body is
    /// at least as rested as usual). Score falls linearly to 0 as RHR climbs
    /// `recoveryMaxElevationBpm` or more above baseline.
    ///
    /// - Returns: `nil` if today or the baseline days have no resting heart rate
    ///   sample — not every day necessarily has one.
    static func recoveryScore(today: DailyMetrics, priorDays: [DailyMetrics]) -> ScoreResult? {
        guard let todayRHR = today.restingHeartRate else { return nil }
        let baselineSamples = priorDays.compactMap(\.restingHeartRate)
        guard !baselineSamples.isEmpty else { return nil }

        let baselineRHR = average(baselineSamples)
        let elevation = max(todayRHR - baselineRHR, 0)
        let percent = (1 - min(elevation / recoveryMaxElevationBpm, 1)) * 100

        let verdict: String
        switch percent {
        case 90...: verdict = "strong recovery"
        case 60..<90: verdict = "solid recovery"
        case 40..<60: verdict = "below baseline"
        default: verdict = "well below baseline"
        }

        let detail = MetricScoreBreakdown(
            metricName: "Resting Heart Rate",
            todayValue: todayRHR,
            baselineValue: baselineRHR,
            unit: "bpm",
            contributionPercent: percent,
            summary: "\(formatted(todayRHR))/\(formatted(baselineRHR)) bpm → \(verdict)"
        )

        return ScoreResult(score: Int(percent.rounded()), breakdown: [detail])
    }

    // MARK: - Score bands (shared by Theme for ring colors, and by coachingMessage below)

    // `Equatable` isn't automatic for enums — the compiler will synthesize it for a
    // simple case-only enum like this, but only once you declare the conformance.
    // Needed so tests can write `XCTAssertEqual(ScoreEngine.band(for: 50), .medium)`.
    enum Band: Equatable {
        case low, medium, high
    }

    static let lowBandThreshold = 40
    static let highBandThreshold = 75

    static func band(for score: Int) -> Band {
        switch score {
        case ..<lowBandThreshold: return .low
        case lowBandThreshold..<highBandThreshold: return .medium
        default: return .high
        }
    }

    /// A one-sentence, plain-language takeaway combining both scores — the kind of
    /// "so what should I actually do" line a coach might give, generated from simple,
    /// explicit rules rather than anything fuzzy. Only the four "both extreme" corners
    /// get bespoke advice; anything with a medium score in either dimension gets a
    /// neutral fallback, since a confident-sounding message isn't warranted there.
    static func coachingMessage(workoutScore: Int, recoveryScore: Int) -> String {
        switch (band(for: workoutScore), band(for: recoveryScore)) {
        case (.high, .high):
            return "Strong effort and well recovered — a great balance today."
        case (.high, .low):
            return "Strong effort despite lower recovery. Keep an eye on rest tonight."
        case (.low, .high):
            return "Well recovered but light on activity — a good day to add some movement."
        case (.low, .low):
            return "Your body needs care. Favor light activity and focus on rest."
        default:
            return "Steady day — on track with your own normal effort and recovery."
        }
    }

    // MARK: - Per-metric breakdown

    private static func breakdown(
        metricName: String,
        today: Double,
        baseline: Double,
        unit: String
    ) -> MetricScoreBreakdown {
        let percent = cappedPercentOfBaseline(today: today, baseline: baseline)
        return MetricScoreBreakdown(
            metricName: metricName,
            todayValue: today,
            baselineValue: baseline,
            unit: unit,
            contributionPercent: percent,
            summary: summary(today: today, baseline: baseline, unit: unit, percent: percent)
        )
    }

    /// Today's value as a percentage of baseline, capped at 100. Handles the
    /// baseline-is-zero edge case explicitly rather than dividing by zero.
    private static func cappedPercentOfBaseline(today: Double, baseline: Double) -> Double {
        guard baseline > 0 else {
            // No baseline activity to compare against: full credit for any activity at
            // all, zero credit for none — there's no meaningful ratio to compute.
            return today > 0 ? 100 : 0
        }
        return min(today / baseline, 1.0) * 100
    }

    private static func summary(today: Double, baseline: Double, unit: String, percent: Double) -> String {
        let verdict: String
        switch percent {
        case 90...: verdict = "strong"
        case 60..<90: verdict = "solid"
        case 40..<60: verdict = "below baseline"
        default: verdict = "well below baseline"
        }
        return "\(formatted(today))/\(formatted(baseline)) \(unit) → \(verdict)"
    }

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
