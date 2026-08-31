import SwiftUI

/// Groups the two score rings (Workout, Recovery) with a plain-language coaching line
/// underneath, in one card — the "rings + one-line takeaway" pattern common to
/// WHOOP/Bevel-style dashboards, built here from Rebase's own data, formula, and
/// copy rather than reusing anyone else's design directly.
struct TodaySummaryCard: View {
    let workoutScore: Int
    // Optional: Recovery needs a resting-heart-rate sample, which can be missing
    // (fresh Simulator, a day with no reading) even when the workout score isn't.
    let recoveryScore: Int?

    private var coachingMessage: String {
        guard let recoveryScore else {
            return "Recovery needs at least one resting heart rate reading — showing your workout effort for now."
        }
        return ScoreEngine.coachingMessage(workoutScore: workoutScore, recoveryScore: recoveryScore)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                Spacer()
                ScoreRingView(score: workoutScore, label: "Workout", diameter: 150, lineWidth: 9)
                Spacer()

                Rectangle()
                    .fill(Theme.secondaryText.opacity(0.2))
                    .frame(width: 1, height: 110)

                Spacer()
                ScoreRingView(score: recoveryScore, label: "Recovery", diameter: 150, lineWidth: 9)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("COACHING")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.secondaryText)
                    .tracking(1.5)
                Text(coachingMessage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        TodaySummaryCard(workoutScore: 96, recoveryScore: 69)
            .padding()
    }
}
