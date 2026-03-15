import Foundation

struct DailyStats: Identifiable {
    let date: String
    let sessionCount: Int
    let totalTokens: Int

    var id: String { date }

    var totalCost: Double {
        Double(totalTokens) * 0.000015
    }
}

struct ProjectStats: Identifiable {
    let projectName: String
    let sessionCount: Int
    let totalTokens: Int

    var id: String { projectName }

    var displayName: String {
        var name = projectName
        while name.hasPrefix("-") {
            name = String(name.dropFirst())
        }
        return name.replacingOccurrences(of: "-", with: "/")
    }
}

struct WidgetData {
    let todaySessions: Int
    let todayTokens: Int
    let todayCost: Double
    let weekSessions: Int
    let weekTokens: Int
    let weekCost: Double
    let topProjects: [ProjectStats]
    let dailyHistory: [DailyStats]
    let focusScore: Double
}
