import SwiftUI

/// A circular progress ring displaying one score, styled like WHOOP/Bevel-style
/// dashboards. Built from two overlaid `Circle` shapes:
///  - a dim full circle as the background "track"
///  - a circle `.trim`-med from 0 to `score / 100` as the colored "progress" arc
/// `.rotationEffect(-90°)` spins the whole thing so progress starts at 12 o'clock
/// (SwiftUI circles start their trim at 3 o'clock by default) and sweeps clockwise.
///
/// `diameter` and `lineWidth` are parameters, not hardcoded, because PulseScore shows
/// two of these side by side (Workout, Recovery) at a shared size — a single fixed
/// size would only work for one usage.
///
/// `score` is `Int?`, not `Int` — Recovery specifically can have no data yet (no
/// resting-heart-rate sample) even when Workout does, since they come from different
/// HealthKit metrics. Rather than block the whole dashboard on that, this ring just
/// renders an empty dim track and "--" for whichever score isn't available yet.
struct ScoreRingView: View {
    let score: Int?
    let label: String
    var diameter: CGFloat = 220
    var lineWidth: CGFloat = 12

    // A computed property — no stored value, just a formula that runs each time it's
    // read. `min(max(score, 0), 100)` clamps in case bad data ever produces <0 or >100
    // so the ring can't visually overflow.
    private var progress: Double {
        guard let score else { return 0 }
        return Double(min(max(score, 0), 100)) / 100.0
    }

    private var ringColor: Color {
        guard let score else { return Theme.secondaryText.opacity(0.3) }
        return Theme.color(forScore: score)
    }

    // Every SwiftUI `View` must have a `body`. `some View` means "a specific concrete
    // type conforming to View, decided by what's returned here" — the compiler infers
    // the real type, we just promise it's *some* single, consistent one.
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.cardBackground, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Animates the ring filling in whenever `progress` changes, instead of
                // snapping instantly.
                .animation(.easeOut(duration: 0.8), value: progress)

            VStack(spacing: 4) {
                // `score.map(String.init)` turns `Int?` into `String?` only if a value
                // exists (never runs `String.init` on a missing value), then `?? "--"`
                // supplies the placeholder — one line instead of an if/else.
                Text(score.map(String.init) ?? "--")
                    // Scaled off diameter so the number stays proportional whether this
                    // is the one big hero ring or one of two smaller side-by-side ones.
                    .font(.system(size: diameter * 0.29, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.secondaryText)
                    .tracking(1.2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// `#Preview` is a macro (Xcode 15+) that renders this view live in Xcode's canvas
// without running the whole app in the Simulator — handy for iterating on one
// component at a time.
#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        ScoreRingView(score: 78, label: "Workout")
    }
}
