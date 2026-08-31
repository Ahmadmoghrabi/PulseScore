import SwiftUI
import Charts // Apple's declarative charting framework — separate import from SwiftUI

/// A 7-day trend of daily scores: one straight `LineMark` connecting each day to the
/// next (so the up/down shape reads at a glance), with a `PointMark` dot at each day
/// colored by that day's own low/medium/high band — the same color language used by
/// the score rings and metric tiles everywhere else in the app.
struct TrendChartView: View {
    let history: [ScoreHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-DAY TREND")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.secondaryText)
                .tracking(1.5)

            // `Chart` takes a collection of Identifiable data and a closure describing
            // one mark per element — similar in spirit to `ForEach`, but building chart
            // geometry instead of views. Returning two marks from the closure (line +
            // point) draws both for every day, layered on the same axes.
            Chart(history) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Score", point.score)
                )
                // `.linear` draws a straight segment dot-to-dot, rather than a smoothed
                // curve — a curve can visually overshoot between points, which would
                // misrepresent the actual daily values. Straight lines stay honest.
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .foregroundStyle(Theme.secondaryText.opacity(0.5))

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Theme.color(forScore: point.score))
                .symbolSize(90)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100])
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        TrendChartView(history: MockData.trend)
            .padding()
    }
}
