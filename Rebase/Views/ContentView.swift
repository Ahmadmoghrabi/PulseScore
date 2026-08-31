import SwiftUI

/// Rebase's main (and, for now, only) screen. Reads real data from
/// `HealthKitManager` and switches on its `state` to show a loading spinner, a
/// permission-denied message, a not-enough-data message, or the real dashboard —
/// the graceful states the original spec called for.
struct ContentView: View {
    // `@State` on a reference type (a class) works the same way it does for a struct:
    // SwiftUI owns this instance for the view's lifetime and re-renders whenever any
    // of its `@Observable`-tracked properties change — no `@StateObject` needed, that
    // was the pre-iOS-17 way to hold an observable reference type safely.
    @State private var healthKitManager = HealthKitManager()

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Rebase")
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                #if DEBUG
                // Debug-only: seeds 14 days of sample data into the Simulator's
                // HealthKit store, then reloads. Compiled out of Release builds
                // entirely, so this button (and the write access it requests) never
                // ships — see HealthKitManager.seedSampleDataForTesting().
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Seed Data") {
                            Task {
                                let seeded = await healthKitManager.seedSampleDataForTesting()
                                if seeded {
                                    await healthKitManager.load()
                                }
                            }
                        }
                    }
                }
                #endif
        }
        .preferredColorScheme(.dark)
        // `.task` runs its closure once when the view first appears (and cancels it
        // automatically if the view disappears first) — the standard SwiftUI place to
        // kick off an async operation like a HealthKit fetch.
        .task {
            await healthKitManager.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch healthKitManager.state {
        case .loading:
            statusView(
                systemImage: nil,
                title: "Loading your activity…",
                message: nil
            )
        case .authorizationDenied:
            statusView(
                systemImage: "heart.slash",
                title: "Health Access Needed",
                message: "Rebase needs permission to read your activity data. Enable it in Settings \u{2192} Privacy \u{2192} Health \u{2192} Rebase."
            )
        case .notEnoughData:
            statusView(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Not Enough Data Yet",
                message: "Rebase needs at least a week of activity history to compute your baseline. Check back after a few more days of tracked activity."
            )
        case .failed(let message):
            statusView(
                systemImage: "exclamationmark.triangle",
                title: "Something Went Wrong",
                message: message
            )
        case .loaded:
            dashboard
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let workout = healthKitManager.todayResult {
                    TodaySummaryCard(
                        workoutScore: workout.score,
                        recoveryScore: healthKitManager.recoveryResult?.score
                    )
                    .padding(.top, 12)

                    // Three equal-width flexible columns lay the tiles out in a row and
                    // wrap to a new row automatically if there were ever more than 3.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(workout.breakdown) { item in
                            MetricCardView(breakdown: item, systemImage: icon(for: item.metricName))
                        }
                    }
                }

                TrendChartView(history: healthKitManager.trend)
            }
            .padding()
        }
        // Pull-to-refresh: SwiftUI attaches the gesture and spinner to the ScrollView
        // automatically. `load()` only ever runs once otherwise (from `.task` on first
        // appear), so without this there'd be no way to see today's updated numbers —
        // say, right after finishing a workout — without force-quitting and relaunching.
        //
        // `load()` alone can resolve fast enough (a cheap HealthKit round trip) that the
        // system's refresh-control bridging loses track of the "ended refreshing" signal
        // and the spinner sticks forever, even though the data genuinely reloaded — a
        // known SwiftUI `.refreshable` quirk. Racing it against a floor delay guarantees
        // the closure never returns before the animation has had time to register, without
        // ever cutting a slow real load short (we still await `load()` itself either way).
        .refreshable {
            async let reload: Void = healthKitManager.load()
            try? await Task.sleep(for: .milliseconds(400))
            await reload
        }
    }

    private func statusView(systemImage: String?, title: String, message: String?) -> some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView()
                    .tint(Theme.primaryText)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func icon(for metricName: String) -> String {
        switch metricName {
        case "Active Energy": return "flame.fill"
        case "Exercise Minutes": return "figure.run"
        case "Steps": return "shoeprints.fill"
        default: return "heart.fill"
        }
    }
}

#Preview {
    ContentView()
}
