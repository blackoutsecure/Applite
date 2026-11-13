struct AppStatusSummary {
    enum Activity: Equatable {
        case refreshingCatalog
        case checkingApps
        case working(name: String, detail: String)
        case downloading(name: String, fraction: Double)
        case failedTasks(Int)
        case updateCheckFailed
        case ready

        var isBusy: Bool {
            switch self {
            case .refreshingCatalog, .checkingApps, .working, .downloading: true
            case .failedTasks, .updateCheckFailed, .ready: false
            }
        }
    }

    let activity: Activity
    let taskCount: Int
    let activeTaskCount: Int
    let failedTaskCount: Int

    init(
        isRefreshingCatalog: Bool,
        isResolvingInstalledState: Bool,
        outdatedRefreshFailed: Bool,
        operations: [(name: String, progress: CaskProgressState)]
    ) {
        let active = operations.compactMap { operation -> Activity? in
            switch operation.progress {
            case .busy(let detail): .working(name: operation.name, detail: detail)
            case .downloading(let fraction): .downloading(name: operation.name, fraction: fraction)
            case .idle, .success, .failed: nil
            }
        }
        taskCount = operations.count
        activeTaskCount = active.count
        failedTaskCount = operations.filter { $0.progress.isFailed }.count

        if isRefreshingCatalog {
            activity = .refreshingCatalog
        } else if let first = active.first {
            activity = first
        } else if isResolvingInstalledState {
            activity = .checkingApps
        } else if failedTaskCount > 0 {
            activity = .failedTasks(failedTaskCount)
        } else if outdatedRefreshFailed {
            activity = .updateCheckFailed
        } else {
            activity = .ready
        }
    }
}
