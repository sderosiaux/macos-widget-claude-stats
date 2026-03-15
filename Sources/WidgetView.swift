import SwiftUI

struct WidgetView: View {
    let store: StatsStore
    let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            contentSection
            ResizeHandle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.refresh() }
        .onReceive(timer) { _ in
            Task { await store.refresh() }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Text("Claude Code")
                .font(.title3)
                .fontWeight(.bold)
            Spacer()
            if let date = store.lastRefresh {
                Text(date, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            headerMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerMenu: some View {
        Menu {
            Button("Refresh") {
                Task { await store.refresh() }
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var contentSection: some View {
        if let data = store.data {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    todaySection(data)
                    Divider().padding(.horizontal, 12)
                    weekSection(data)
                    Divider().padding(.horizontal, 12)
                    projectsSection(data)
                    Divider().padding(.horizontal, 12)
                    sparklineSection(data)
                    Divider().padding(.horizontal, 12)
                    focusSection(data)
                }
                .padding(.vertical, 6)
            }
        } else {
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private func todaySection(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statCell(label: "Sessions", value: "\(data.todaySessions)")
                statCell(label: "Tokens", value: formatTokens(data.todayTokens))
                statCell(label: "Cost", value: formatCost(data.todayCost))
            }
        }
        .padding(.horizontal, 12)
    }

    private func weekSection(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This Week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statCell(label: "Sessions", value: "\(data.weekSessions)")
                statCell(label: "Tokens", value: formatTokens(data.weekTokens))
                statCell(label: "Cost", value: formatCost(data.weekCost))
            }
        }
        .padding(.horizontal, 12)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func projectsSection(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Top Projects")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            let maxSessions = data.topProjects.map(\.sessionCount).max() ?? 1
            ForEach(data.topProjects) { project in
                ProjectRow(project: project, maxSessions: maxSessions)
            }
        }
    }

    private func sparklineSection(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("7-Day Activity")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            let maxTokens = data.dailyHistory.map(\.totalTokens).max() ?? 1
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(data.dailyHistory) { day in
                    VStack(spacing: 2) {
                        let fraction = CGFloat(day.totalTokens) / CGFloat(maxTokens)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(height: max(4, 40 * fraction))
                        Text(shortDay(day.date))
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 54)
        }
        .padding(.horizontal, 12)
    }

    private func focusSection(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Focus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", data.focusScore * 100))
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(focusColor(data.focusScore))
                        .frame(width: geo.size.width * data.focusScore)
                }
            }
            .frame(height: 6)
            Text(focusLabel(data.focusScore))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
    }

    private func focusColor(_ score: Double) -> Color {
        if score < 0.3 {
            return .red
        } else if score < 0.6 {
            return .orange
        } else {
            return .green
        }
    }

    private func focusLabel(_ score: Double) -> String {
        if score < 0.3 {
            return "Scattered across many projects"
        } else if score < 0.6 {
            return "Moderate focus"
        } else {
            return "Deep focus on few projects"
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    private func shortDay(_ dateStr: String) -> String {
        // Input: "2026-03-15", output: "15"
        let parts = dateStr.components(separatedBy: "-")
        guard parts.count == 3 else { return dateStr }
        return parts[2]
    }
}
