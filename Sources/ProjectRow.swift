import SwiftUI

struct ProjectRow: View {
    let project: ProjectStats
    let maxSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(project.sessionCount)s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let fraction = maxSessions > 0
                    ? CGFloat(project.sessionCount) / CGFloat(maxSessions)
                    : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: geo.size.width * fraction, height: 4)
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
