import Foundation
import Observation

@Observable
final class StatsStore {
    var data: WidgetData?
    var lastRefresh: Date?

    @MainActor
    func refresh() async {
        let result = await Task.detached {
            StatsService.fetchAll()
        }.value
        self.data = result
        self.lastRefresh = Date()
    }
}
