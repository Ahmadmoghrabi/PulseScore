import Foundation

/// One day's worth of activity data — whether it came from HealthKit or mock data,
/// this is the shape the rest of the app (ScoreEngine, views) works with. Keeping
/// HealthKit's types (HKQuantitySample, HKUnit, etc.) out of this struct is what lets
/// ScoreEngine stay pure Swift with no `import HealthKit`.
///
/// `struct` (not `class`) because this is a plain value: two `DailyMetrics` with the
/// same fields should just *be* equal, and nobody should be able to mutate one out from
/// under another part of the app that's holding a reference to it. Swift structs are
/// copied on assignment, which gives us that for free — no `equals()`/`hashCode()`
/// boilerplate like Java, no need for `@dataclass` like Python.
struct DailyMetrics: Identifiable {
    // `Identifiable` is a protocol requiring an `id` property. SwiftUI's `ForEach`
    // uses it to tell list items apart across UI updates. Rather than store a
    // separate id, we compute one from `date` — each day is already unique.
    var id: Date { date }

    let date: Date
    let activeEnergy: Double      // kilocalories
    let exerciseMinutes: Double   // Apple Exercise minutes
    let steps: Double
    let restingHeartRate: Double? // bpm; Optional because not every day has a reading
}
