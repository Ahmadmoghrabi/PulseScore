import XCTest
@testable import PulseScore

/// `@testable import` gives this test target visibility into PulseScore's internal
/// (non-`public`) types — normally an app target's types aren't visible outside it,
/// but Xcode relaxes that specifically for the paired test target.
final class ScoreEngineTests: XCTestCase {

    /// Small helper so each test doesn't repeat DailyMetrics boilerplate. `daysAgo`
    /// defaults to 0 (today) since most tests only care about the numeric values.
    private func metrics(
        activeEnergy: Double,
        exerciseMinutes: Double,
        steps: Double,
        restingHeartRate: Double? = nil,
        daysAgo: Int = 0
    ) -> DailyMetrics {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return DailyMetrics(
            date: date,
            activeEnergy: activeEnergy,
            exerciseMinutes: exerciseMinutes,
            steps: steps,
            restingHeartRate: restingHeartRate
        )
    }

    func testMatchingBaselineExactlyScoresOneHundred() {
        let baseline = (1...7).map { metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000, daysAgo: $0) }
        let today = metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000)

        let result = ScoreEngine.score(today: today, priorDays: baseline)

        XCTAssertEqual(result?.score, 100)
    }

    func testZeroActivityScoresZero() {
        let baseline = (1...7).map { metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000, daysAgo: $0) }
        let today = metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0)

        let result = ScoreEngine.score(today: today, priorDays: baseline)

        XCTAssertEqual(result?.score, 0)
    }

    func testExceedingBaselineIsCappedNotBonused() {
        let baseline = (1...7).map { metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000, daysAgo: $0) }
        let double = metrics(activeEnergy: 800, exerciseMinutes: 60, steps: 16000)
        let triple = metrics(activeEnergy: 1200, exerciseMinutes: 90, steps: 24000)

        let doubleResult = ScoreEngine.score(today: double, priorDays: baseline)
        let tripleResult = ScoreEngine.score(today: triple, priorDays: baseline)

        // Both blow past baseline — both should cap at the same max (100), not have
        // the triple-baseline day score higher than the double-baseline day.
        XCTAssertEqual(doubleResult?.score, 100)
        XCTAssertEqual(tripleResult?.score, 100)
    }

    func testMixedValuesProduceExpectedWeightedScore() {
        let baseline = (1...7).map { metrics(activeEnergy: 400, exerciseMinutes: 40, steps: 10000, daysAgo: $0) }
        // 50% of active energy baseline, 100% of exercise baseline, 25% of steps baseline.
        let today = metrics(activeEnergy: 200, exerciseMinutes: 40, steps: 2500)

        let result = ScoreEngine.score(today: today, priorDays: baseline)

        // 50*0.40 + 100*0.35 + 25*0.25 = 20 + 35 + 6.25 = 61.25 → rounds to 61
        XCTAssertEqual(result?.score, 61)
    }

    func testEmptyBaselineReturnsNil() {
        let today = metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000)

        let result = ScoreEngine.score(today: today, priorDays: [])

        XCTAssertNil(result)
    }

    func testResultingHeartRateNeverAppearsInWorkoutScoreBreakdown() {
        // Resting heart rate now feeds a separate Recovery score entirely (see the
        // recoveryScore tests below) — the Workout Score breakdown should never
        // mention it, whether or not a reading is present.
        let baseline = (1...7).map {
            metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000, restingHeartRate: 60, daysAgo: $0)
        }
        let today = metrics(activeEnergy: 400, exerciseMinutes: 30, steps: 8000, restingHeartRate: 50)

        let result = ScoreEngine.score(today: today, priorDays: baseline)

        XCTAssertEqual(result?.breakdown.count, 3)
        XCTAssertFalse(result?.breakdown.contains { $0.metricName == "Resting Heart Rate" } ?? true)
    }

    // MARK: - recoveryScore

    func testRecoveryAtOrBelowBaselineScoresOneHundred() {
        let baseline = (1...7).map { metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 60, daysAgo: $0) }
        let today = metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 55) // below baseline

        let result = ScoreEngine.recoveryScore(today: today, priorDays: baseline)

        XCTAssertEqual(result?.score, 100)
    }

    func testRecoveryFallsLinearlyAboveBaseline() {
        let baseline = (1...7).map { metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 60, daysAgo: $0) }
        // 5 bpm above baseline, halfway to the 10 bpm "zero recovery" ceiling.
        let today = metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 65)

        let result = ScoreEngine.recoveryScore(today: today, priorDays: baseline)

        XCTAssertEqual(result?.score, 50)
    }

    func testRecoveryAtOrBeyondMaxElevationScoresZero() {
        let baseline = (1...7).map { metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 60, daysAgo: $0) }
        let today = metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 80) // way above baseline

        let result = ScoreEngine.recoveryScore(today: today, priorDays: baseline)

        XCTAssertEqual(result?.score, 0)
    }

    func testRecoveryReturnsNilWithoutRestingHeartRateData() {
        let baseline = (1...7).map { metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, daysAgo: $0) } // no RHR
        let today = metrics(activeEnergy: 0, exerciseMinutes: 0, steps: 0, restingHeartRate: 60)

        XCTAssertNil(ScoreEngine.recoveryScore(today: today, priorDays: baseline))
    }

    // MARK: - band / coachingMessage

    func testBandThresholds() {
        XCTAssertEqual(ScoreEngine.band(for: 0), .low)
        XCTAssertEqual(ScoreEngine.band(for: 39), .low)
        XCTAssertEqual(ScoreEngine.band(for: 40), .medium)
        XCTAssertEqual(ScoreEngine.band(for: 74), .medium)
        XCTAssertEqual(ScoreEngine.band(for: 75), .high)
        XCTAssertEqual(ScoreEngine.band(for: 100), .high)
    }

    func testCoachingMessageCoversBothExtremeCorners() {
        // Just checking each corner produces a distinct, non-empty message — the exact
        // wording is free to change, but every combination should say *something*.
        let highHigh = ScoreEngine.coachingMessage(workoutScore: 90, recoveryScore: 90)
        let highLow = ScoreEngine.coachingMessage(workoutScore: 90, recoveryScore: 20)
        let lowHigh = ScoreEngine.coachingMessage(workoutScore: 20, recoveryScore: 90)
        let lowLow = ScoreEngine.coachingMessage(workoutScore: 20, recoveryScore: 20)

        let messages = Set([highHigh, highLow, lowHigh, lowLow])
        XCTAssertEqual(messages.count, 4, "each extreme corner should have distinct advice")
    }

    func testScoringIsDeterministic() {
        let baseline = (1...7).map { metrics(activeEnergy: 420, exerciseMinutes: 33, steps: 8700, daysAgo: $0) }
        let today = metrics(activeEnergy: 500, exerciseMinutes: 20, steps: 9100)

        let first = ScoreEngine.score(today: today, priorDays: baseline)
        let second = ScoreEngine.score(today: today, priorDays: baseline)

        XCTAssertEqual(first?.score, second?.score)
        XCTAssertEqual(first?.breakdown.map(\.summary), second?.breakdown.map(\.summary))
    }
}
