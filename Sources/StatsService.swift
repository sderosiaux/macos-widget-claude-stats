import Foundation

enum StatsService {
    private static let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-stats-widget.log")

    private static let queryScript: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/plugins/cache/sderosiaux-claude-plugins/claude-warehouse/0.3.0/scripts/query.py"
    }()

    private static var cachedData: WidgetData?

    private static func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: logFile) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logFile.path, contents: data)
        }
    }

    private static func runQuery(_ sql: String) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let rand = Int.random(in: 0...999_999)
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stats-\(pid)-\(rand).txt")

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extraPaths = [
            "\(homeDir)/.bun/bin",
            "\(homeDir)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        env["PATH"] = extraPaths.joined(separator: ":") + ":\(currentPath)"

        let process = Process()
        process.environment = env
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "\(queryScript) sql \"\(sql)\" > \(tmpFile.path) 2>&1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = try Data(contentsOf: tmpFile)
            try? FileManager.default.removeItem(at: tmpFile)
            return String(data: data, encoding: .utf8)
        } catch {
            log("query error: \(error)")
            try? FileManager.default.removeItem(at: tmpFile)
            return nil
        }
    }

    private static func parseRows(_ output: String) -> [[String]] {
        let lines = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }

        // First line is header, second is separator (unicode dashes), rest are data
        let dataLines = lines.dropFirst(2)
        return dataLines.map { line in
            line.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    private static func fetchTodayStats() -> (sessions: Int, tokens: Int) {
        let sql = """
            SELECT COUNT(*) as sessions, \
            COALESCE(SUM(total_input_tokens + total_output_tokens), 0) as tokens \
            FROM sessions WHERE created_at >= current_date
            """
        guard let output = runQuery(sql) else { return (0, 0) }
        let rows = parseRows(output)
        guard let row = rows.first, row.count >= 2 else { return (0, 0) }
        return (Int(row[0]) ?? 0, Int(row[1]) ?? 0)
    }

    private static func fetchWeekStats() -> (sessions: Int, tokens: Int) {
        let sql = """
            SELECT COUNT(*) as sessions, \
            COALESCE(SUM(total_input_tokens + total_output_tokens), 0) as tokens \
            FROM sessions WHERE created_at >= current_date - INTERVAL '7 days'
            """
        guard let output = runQuery(sql) else { return (0, 0) }
        let rows = parseRows(output)
        guard let row = rows.first, row.count >= 2 else { return (0, 0) }
        return (Int(row[0]) ?? 0, Int(row[1]) ?? 0)
    }

    private static func fetchTopProjects() -> [ProjectStats] {
        let sql = """
            SELECT project_name, COUNT(*) as sessions, \
            SUM(total_input_tokens + total_output_tokens) as tokens \
            FROM sessions WHERE created_at >= current_date - INTERVAL '7 days' \
            GROUP BY 1 ORDER BY sessions DESC LIMIT 5
            """
        guard let output = runQuery(sql) else { return [] }

        let lines = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }

        let dataLines = Array(lines.dropFirst(2))
        return dataLines.compactMap { line in
            // Project names can contain spaces from truncation, so parse from the right
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Split by two or more spaces to separate columns
            let parts = splitColumns(trimmed)
            guard parts.count >= 3 else { return nil }

            let tokens = Int(parts[parts.count - 1]) ?? 0
            let sessions = Int(parts[parts.count - 2]) ?? 0
            let name = parts.dropLast(2).joined(separator: " ")

            return ProjectStats(projectName: name, sessionCount: sessions, totalTokens: tokens)
        }
    }

    private static func fetchDailyHistory() -> [DailyStats] {
        let sql = """
            SELECT CAST(created_at AS DATE) as day, COUNT(*) as sessions, \
            SUM(total_input_tokens + total_output_tokens) as tokens \
            FROM sessions WHERE created_at >= current_date - INTERVAL '7 days' \
            GROUP BY 1 ORDER BY 1
            """
        guard let output = runQuery(sql) else { return [] }
        let rows = parseRows(output)
        return rows.compactMap { row in
            guard row.count >= 3 else { return nil }
            return DailyStats(
                date: row[0],
                sessionCount: Int(row[1]) ?? 0,
                totalTokens: Int(row[2]) ?? 0
            )
        }
    }

    private static func splitColumns(_ line: String) -> [String] {
        // Split on 2+ whitespace characters to handle column separation
        var parts: [String] = []
        var current = ""
        var spaceCount = 0

        for ch in line {
            if ch == " " {
                spaceCount += 1
            } else {
                if spaceCount >= 2 && !current.isEmpty {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else if spaceCount > 0 {
                    current += String(repeating: " ", count: spaceCount)
                }
                spaceCount = 0
                current.append(ch)
            }
        }
        if !current.isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts
    }

    private static func computeFocusScore(_ projects: [ProjectStats]) -> Double {
        let totalSessions = projects.reduce(0) { $0 + $1.sessionCount }
        guard totalSessions > 0 else { return 0.0 }

        // Herfindahl index: sum of squared shares
        let hhi = projects.reduce(0.0) { sum, project in
            let share = Double(project.sessionCount) / Double(totalSessions)
            return sum + share * share
        }
        return hhi
    }

    static func fetchAll() -> WidgetData {
        log("fetch started")

        let today = fetchTodayStats()
        let week = fetchWeekStats()
        let projects = fetchTopProjects()
        let daily = fetchDailyHistory()
        let focus = computeFocusScore(projects)

        let data = WidgetData(
            todaySessions: today.sessions,
            todayTokens: today.tokens,
            todayCost: Double(today.tokens) * 0.000015,
            weekSessions: week.sessions,
            weekTokens: week.tokens,
            weekCost: Double(week.tokens) * 0.000015,
            topProjects: projects,
            dailyHistory: daily,
            focusScore: focus
        )

        log("fetch done: today=\(today.sessions)s/\(today.tokens)t week=\(week.sessions)s")
        cachedData = data
        return data
    }

    static func fetchCached() -> WidgetData? {
        cachedData
    }
}
