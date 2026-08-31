import SwiftUI

/// One compact square tile for a single metric — icon, today's value, the metric
/// name, and a small percent-of-baseline readout colored by the same low/medium/high
/// band language used everywhere else (rings, trend dots). Three of these sit side by
/// side in a row, so every element has to stay small and self-explanatory at a glance.
struct MetricCardView: View {
    let breakdown: MetricScoreBreakdown
    let systemImage: String // SF Symbols name, e.g. "flame.fill"

    // `contributionPercent` is already 0...100, the same scale ScoreEngine's overall
    // score uses — so the exact same band/color logic applies here directly.
    private var verdictColor: Color {
        Theme.color(forScore: Int(breakdown.contributionPercent))
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 30, height: 30)
                .background(Theme.background)
                .clipShape(Circle())

            Text(formattedValue)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7) // shrinks text instead of clipping/wrapping
                                          // if a value is too wide for the tile (e.g. "12,000")

            Text(breakdown.metricName)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(Int(breakdown.contributionPercent))% of baseline")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(verdictColor)
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        // Forces the tile to stay square regardless of how wide the grid column ends
        // up being — width and height always match.
        .aspectRatio(1, contentMode: .fit)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // The tile itself only shows a percentage, but VoiceOver users get the full
        // plain-language sentence ScoreEngine already generated ("420/380 cal →
        // strong") — nothing is lost, it's just not printed on screen at this size.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(breakdown.metricName): \(breakdown.summary)")
    }

    private var formattedValue: String {
        let value = breakdown.todayValue
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        HStack(spacing: 12) {
            ForEach(MockData.todayResult.breakdown) { item in
                MetricCardView(breakdown: item, systemImage: "flame.fill")
            }
        }
        .padding()
    }
}
