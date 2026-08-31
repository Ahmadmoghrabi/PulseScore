# PulseScore — Step 3 plan: wire in real HealthKit data

Status when this was written: Steps 1 and 2 are done. `ScoreEngine` is fully built and
unit-tested (13 passing tests). The UI (two-ring summary card, square metric tiles,
line-and-dot trend chart, custom app icon) is complete and running against
`MockData`. Nothing in HealthKit has been touched yet — this file is the plan for that,
written so a fresh session (or a fresh set of eyes) can pick it up without re-deriving
any of the above.

## What's already in place (no action needed)

- The `PulseScore.entitlements` file already declares `com.apple.developer.healthkit: true`
  (set in `project.yml` back in Step 1).
- `INFOPLIST_KEY_NSHealthShareUsageDescription` is already set in `project.yml` — the
  permission prompt text is ready.
- `DailyMetrics`, `ScoreResult`, `MetricScoreBreakdown` are the exact shape
  `HealthKitManager` needs to produce — `ScoreEngine` and every view already consume
  these types and don't know or care where they came from. That's the payoff of the
  architecture: this step should only touch two things (a new `HealthKitManager` file,
  and `ContentView`), nothing else.

## Steps

1. **Create `PulseScore/HealthKit/HealthKitManager.swift`.**
   - `import HealthKit`.
   - An `@Observable` class (iOS 17+ macro) holding an `HKHealthStore` instance, plus
     published-ish state SwiftUI can react to: something like
     `enum LoadState { case loading, authorizationDenied, noData, loaded, failed(Error) }`
     and `var state: LoadState`, `var todayResult: ScoreResult?`,
     `var recoveryResult: ScoreResult?`, `var trend: [ScoreHistoryPoint]`.
   - Guard `HKHealthStore.isHealthDataAvailable()` before doing anything else.

2. **Define the four read types** as `HKQuantityType`s:
   `.activeEnergyBurned`, `.appleExerciseTime`, `.stepCount`, `.restingHeartRate`.
   Request authorization with `healthStore.requestAuthorization(toShare: [], read: readTypes)`
   — read-only, matches the spec.

3. **Fetch 14 days of data with `HKStatisticsCollectionQuery`**, one query per metric,
   bucketed by day (`.cumulativeSum` for energy/exercise/steps, `.discreteAverage` for
   resting heart rate) — NOT 14 separate single-day queries. One query per metric
   covering the whole window is the idiomatic HealthKit pattern and far fewer round
   trips. HealthKit's query APIs are completion-handler based, not native async yet —
   bridge each with `withCheckedThrowingContinuation` to use them with `async/await`
   the same way the rest of the app already does.

4. **Assemble `[DailyMetrics]`** from the four per-metric daily buckets (same struct
   `MockData` already builds), then call the *existing, untouched* `ScoreEngine.score`
   and `ScoreEngine.recoveryScore` — no changes needed there.

5. **Update `ContentView`**: replace the `MockData` properties with
   `@State private var healthKitManager = HealthKitManager()`, add
   `.task { await healthKitManager.load() }`, and `switch healthKitManager.state` to
   show: a loading spinner, an authorization-denied state (with a button/link to open
   Settings), a "not enough data yet" empty state (this is the same `nil`-returning
   contract `ScoreEngine` already has — reuse it, don't invent a new one), or the real
   dashboard. `ScoreRingView`, `MetricCardView`, `TrendChartView`, `TodaySummaryCard`
   need zero changes — they only ever consumed `ScoreResult`/`DailyMetrics`, never
   HealthKit types directly.

6. **Testing on Simulator**: the Simulator's Health app can have sample data entered
   by hand (Health app → Browse → search each metric → Add Data). Note that a *fresh*
   Simulator very likely has zero resting-heart-rate data — expect to see the
   "not enough data" state immediately for Recovery, which is a good opportunity to
   confirm that state actually renders correctly, not a bug to chase.

7. **Testing on a real device**: requires Signing & Capabilities → Team set to your
   Apple ID, running on a physical iPhone, and the device having a real activity
   history. If the phone is a light Apple Watch/iPhone-activity user, the 7-day
   baseline may be sparse — this is exactly the scenario the `nil`-returning
   "not enough data" contract in `ScoreEngine` was built to handle gracefully.

## After this step

Per the original plan, Step 4 is "connect real data to the score and polish the UI" —
by the time Step 3 is done, that's largely already true (the UI was built against the
same data shapes from day one), so Step 4 becomes more about edge-case polish and any
visual refinement, not a rewire.
