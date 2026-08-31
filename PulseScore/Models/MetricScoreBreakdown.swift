import Foundation

/// The result of scoring a single metric against its baseline. In step 2 this will be
/// produced by `ScoreEngine`; for now we hand-author instances of it as mock data so
/// the views have something real to render. Because the views only ever consume this
/// struct (never HealthKit types or raw HKQuantitySamples), swapping the mock producer
/// for the real ScoreEngine later won't require touching any view code.
struct MetricScoreBreakdown: Identifiable {
    // No natural unique field here (two metrics could share a name in theory), so we
    // generate a random id. `let id = UUID()` runs once when the struct is created.
    let id = UUID()

    let metricName: String
    let todayValue: Double
    let baselineValue: Double
    let unit: String
    let contributionPercent: Double // this metric's percent-of-baseline, capped at 100
    let summary: String             // plain-language, e.g. "420/380 cal → strong"
}
