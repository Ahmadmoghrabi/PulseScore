import Foundation
import HealthKit

/// Pulls the last 14 days of activity from Apple Health and turns it into the same
/// `ScoreResult`/`ScoreHistoryPoint` shapes `MockData` was already producing — so
/// `ScoreEngine` and every view needed zero changes to go from mock data to real data.
///
/// `@Observable` (the Observation framework, iOS 17+) makes every stored property here
/// automatically trackable by SwiftUI: a view holding this in `@State` re-renders
/// whenever `state`, `todayResult`, etc. change, with no `@Published` properties or
/// `ObservableObject` conformance needed — that machinery was how this worked pre-iOS 17.
@Observable
final class HealthKitManager {

    /// Every state the dashboard needs to render something reasonable for, per the
    /// original spec: a loading spinner, a denied-permission message, an empty state
    /// when there isn't enough history yet, or the real dashboard.
    enum LoadState: Equatable {
        case loading
        case authorizationDenied
        case notEnoughData
        case loaded
        case failed(String)
    }

    private let healthStore = HKHealthStore()

    private(set) var state: LoadState = .loading
    private(set) var todayResult: ScoreResult?
    private(set) var recoveryResult: ScoreResult?
    private(set) var trend: [ScoreHistoryPoint] = []

    // `quantityType(forIdentifier:)` returns an Optional in general, but for Apple's
    // own standard identifiers like these it can never actually fail — force-unwrapping
    // a guaranteed-valid system identifier is the accepted pattern in HealthKit code
    // (Apple's own sample code does the same).
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let restingHeartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!

    /// Requests permission, fetches history, and computes both scores. Safe to call
    /// from a SwiftUI `.task` — it never throws, every failure is captured in `state`.
    func load() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .failed("Health data isn't available on this device.")
            return
        }

        let readTypes: Set<HKObjectType> = [activeEnergyType, exerciseTimeType, stepType, restingHeartRateType]

        do {
            // HealthKit added a native async overload of this method — no manual
            // completion-handler bridging needed on iOS 17.
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            state = .authorizationDenied
            return
        }

        do {
            let history = try await fetchFourteenDayHistory()
            let windowSize = ScoreEngine.baselineWindowDays

            // `history` always has exactly 14 entries regardless of whether HealthKit
            // found any real samples — missing days are filled with 0/nil, not omitted.
            // So the real "not enough data" signal isn't the day count, it's whether
            // any actual activity exists anywhere in the window. Without this check, a
            // brand-new Health store (fresh Simulator, or a device that's never tracked
            // anything) renders as a *real* score of 0 instead of "we don't know yet" —
            // found by actually running this on the Simulator, not by inspection.
            let hasAnyRecordedActivity = history.contains {
                $0.activeEnergy > 0 || $0.exerciseMinutes > 0 || $0.steps > 0
            }

            guard hasAnyRecordedActivity, let today = history.last else {
                state = .notEnoughData
                return
            }

            let priorDays = Array(history.suffix(windowSize + 1).dropLast())

            guard let workout = ScoreEngine.score(today: today, priorDays: priorDays) else {
                state = .notEnoughData
                return
            }

            todayResult = workout
            // Recovery can legitimately be nil (no resting-heart-rate sample yet) even
            // when the workout score is available — that's fine, the UI shows the
            // workout ring alone rather than blocking on a stricter all-or-nothing state.
            recoveryResult = ScoreEngine.recoveryScore(today: today, priorDays: priorDays)
            trend = computeTrend(from: history, windowSize: windowSize)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func computeTrend(from history: [DailyMetrics], windowSize: Int) -> [ScoreHistoryPoint] {
        let trendStartIndex = history.count - windowSize
        guard trendStartIndex >= windowSize else { return [] }
        return (trendStartIndex..<history.count).compactMap { index in
            let today = history[index]
            let priorDays = Array(history[(index - windowSize)..<index])
            guard let result = ScoreEngine.score(today: today, priorDays: priorDays) else { return nil }
            return ScoreHistoryPoint(date: today.date, score: result.score)
        }
    }

    /// Builds one `DailyMetrics` per day for the last 14 days by running one
    /// `HKStatisticsCollectionQueryDescriptor` per metric — each covers the whole
    /// window bucketed by day in a single round trip, rather than 14 separate
    /// single-day queries. `async let` runs all four metric queries concurrently
    /// since none of them depend on each other.
    private func fetchFourteenDayHistory() async throws -> [DailyMetrics] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let startDate = calendar.date(byAdding: .day, value: -13, to: startOfToday)!
        let endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday)! // exclusive upper bound

        async let activeEnergyByDay = dailyStatistic(
            for: activeEnergyType, unit: .kilocalorie(), option: .cumulativeSum, start: startDate, end: endDate
        )
        async let exerciseByDay = dailyStatistic(
            for: exerciseTimeType, unit: .minute(), option: .cumulativeSum, start: startDate, end: endDate
        )
        async let stepsByDay = dailyStatistic(
            for: stepType, unit: .count(), option: .cumulativeSum, start: startDate, end: endDate
        )
        async let restingHRByDay = dailyStatistic(
            for: restingHeartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            option: .discreteAverage,
            start: startDate,
            end: endDate
        )

        let (energy, exercise, steps, restingHR) = try await (activeEnergyByDay, exerciseByDay, stepsByDay, restingHRByDay)

        var days: [DailyMetrics] = []
        var cursor = startDate
        while cursor < endDate {
            days.append(DailyMetrics(
                date: cursor,
                activeEnergy: energy[cursor] ?? 0,
                exerciseMinutes: exercise[cursor] ?? 0,
                steps: steps[cursor] ?? 0,
                restingHeartRate: restingHR[cursor]
            ))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return days
    }

    /// One metric, bucketed into daily totals (`.cumulativeSum`, for energy/exercise/
    /// steps) or daily averages (`.discreteAverage`, for resting heart rate) across the
    /// whole date range in a single query.
    private func dailyStatistic(
        for type: HKQuantityType,
        unit: HKUnit,
        option: HKStatisticsOptions,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: option,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: healthStore)

        var byDay: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let quantity = option == .discreteAverage ? statistics.averageQuantity() : statistics.sumQuantity()
            if let quantity {
                byDay[statistics.startDate] = quantity.doubleValue(for: unit)
            }
        }
        return byDay
    }

    #if DEBUG
    /// DEBUG-only: writes 14 days of synthetic samples into the Simulator's HealthKit
    /// store, so the real query path (`load()` above) can be exercised without waiting
    /// on actual tracked activity or tapping through the Simulator's Health app by
    /// hand. `#if DEBUG` means this entire method — including the `toShare` write
    /// request — is compiled out of Release builds; the shipped app never asks for
    /// write access, staying true to the read-only design in the spec.
    @discardableResult
    func seedSampleDataForTesting() async -> Bool {
        // `appleExerciseTime` is deliberately excluded: HealthKit hard-refuses write
        // access to it for any third-party app (confirmed by an actual crash log —
        // `NSInvalidArgumentException: Authorization to share ...
        // HKQuantityTypeIdentifierAppleExerciseTime is disallowed`). Apple restricts
        // write access to that type, and Stand Time, specifically so apps can't
        // fabricate Activity Ring progress — only Apple's own frameworks can
        // contribute to it. To seed exercise minutes for testing, add them by hand
        // through the Simulator's own Health app instead.
        let writeTypes: Set<HKSampleType> = [activeEnergyType, stepType, restingHeartRateType]
        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: [])
        } catch {
            state = .failed("Seed auth failed: \(error.localizedDescription)")
            return false
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)

        // Same 14-day shape MockData used earlier in development — oldest to newest,
        // ending in "today" — so the seeded dashboard looks familiar.
        let raw: [(activeEnergy: Double, exerciseMinutes: Double, steps: Double, restingHeartRate: Double)] = [
            (320, 22, 6200, 63), (340, 24, 6800, 62), (300, 18, 5800, 63),
            (450, 38, 9200, 60), (500, 42, 10500, 59), (280, 15, 5200, 64),
            (400, 30, 8000, 61), (600, 55, 12000, 57), (250, 12, 4500, 65),
            (380, 28, 7800, 61), (420, 33, 8600, 60), (470, 40, 9800, 59),
            (300, 20, 6000, 63), (420, 28, 9800, 64)
        ]

        var samples: [HKQuantitySample] = []
        for (index, day) in raw.enumerated() {
            let daysAgo = raw.count - 1 - index
            let start = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)!
            let end = calendar.date(byAdding: .hour, value: 12, to: start)!

            samples.append(HKQuantitySample(
                type: activeEnergyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: day.activeEnergy),
                start: start, end: end
            ))
            samples.append(HKQuantitySample(
                type: stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: day.steps),
                start: start, end: end
            ))
            samples.append(HKQuantitySample(
                type: restingHeartRateType,
                quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: day.restingHeartRate),
                start: start, end: end
            ))
        }

        do {
            try await healthStore.save(samples)
            return true
        } catch {
            state = .failed("Seed save failed: \(error.localizedDescription)")
            return false
        }
    }
    #endif
}
