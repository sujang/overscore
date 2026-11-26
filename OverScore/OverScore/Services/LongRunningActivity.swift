import UIKit
import BackgroundTasks
import os

/// 動画の取り込みなど、時間のかかる処理を端末のロックやアプリ切り替えから守る。
///
/// 1. 自動ロックを止める（画面を点けたままにする）
/// 2. iOS 26 以降は `BGContinuedProcessingTask` を使い、手動でロックしたり他のアプリへ
///    切り替えたりしても処理を最後まで続けられるようにする。進捗はシステムのUIに表示される。
/// 3. それ以前の iOS、または 2 が使えないときは `beginBackgroundTask` で数十秒の猶予を得る。
///
/// バックグラウンドの実行期限が切れたら必ずそのタスクを終了する（終了しないとシステムに強制終了される）。
@MainActor
final class LongRunningActivity {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OverScore",
        category: "LongRunningActivity"
    )

    /// 同時に実行中の処理の数。最後の処理が終わったときだけ自動ロックを戻す。
    private static var activeCount = 0

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isActive = false

    /// iOS 26 以降で実行中の継続処理タスク（`BGContinuedProcessingTask`）
    private var continuedTask: AnyObject?
    /// タスク開始前に届いた進捗。開始時に反映する。
    private var latestFraction: Double = 0

    /// 進捗の分母。小数の進捗を整数の completedUnitCount に変換するため細かく刻む。
    private static let progressUnitCount: Int64 = 1000

    /// - Parameters:
    ///   - name: デバッグ用のタスク名
    ///   - title: iOS 26 以降でシステムの進捗表示に出すタイトル
    static func begin(name: String, title: String) -> LongRunningActivity {
        let activity = LongRunningActivity()
        activity.start(name: name, title: title)
        return activity
    }

    private func start(name: String, title: String) {
        isActive = true
        Self.activeCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.endBackgroundTask()
            }
        }
        if #available(iOS 26.0, *) {
            submitContinuedProcessingTask(title: title)
        }
    }

    /// 全体の進捗（0〜1）を報告する。
    /// 継続処理タスクは進捗が止まっていると見なされるとシステムに打ち切られるため、こまめに呼ぶこと。
    func updateProgress(_ fraction: Double) {
        latestFraction = min(max(fraction, 0), 1)
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask {
            Self.apply(latestFraction, to: task.progress)
        }
    }

    /// 処理の終了を伝える。複数回呼んでも安全。
    func end(success: Bool = true) {
        guard isActive else { return }
        isActive = false
        Self.activeCount -= 1
        if Self.activeCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask {
            if success {
                Self.apply(1, to: task.progress)
            }
            task.setTaskCompleted(success: success)
        }
        continuedTask = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private static func apply(_ fraction: Double, to progress: Progress) {
        progress.totalUnitCount = progressUnitCount
        progress.completedUnitCount = Int64(fraction * Double(progressUnitCount))
    }

    // MARK: - BGContinuedProcessingTask (iOS 26+)

    @available(iOS 26.0, *)
    private func submitContinuedProcessingTask(title: String) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // Info.plist の BGTaskSchedulerPermittedIdentifiers に "<bundleID>.import.*" を登録済み
        let identifier = "\(bundleID).import.\(UUID().uuidString)"

        // 継続処理タスクは起動完了後の登録が許されている。ID は毎回一意なので重複登録にならない。
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self?.attach(task)
            }
        }
        guard registered else {
            Self.logger.error("failed to register continued processing task")
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: String(localized: "完了するまでロックしても続行します")
        )
        // すぐに開始できない場合は待たずに諦める（beginBackgroundTask の猶予だけで続ける）
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.logger.error("failed to submit continued processing task: \(error.localizedDescription, privacy: .public)")
        }
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask) {
        guard isActive else {
            // 処理がタスク開始より先に終わっていた
            Self.apply(1, to: task.progress)
            task.setTaskCompleted(success: true)
            return
        }
        continuedTask = task
        Self.apply(latestFraction, to: task.progress)
        task.expirationHandler = { [weak self] in
            // ユーザーがシステムUIから停止した、または進捗が止まったと判断された。
            // 以降は beginBackgroundTask の猶予だけで続ける。
            Task { @MainActor in
                guard let self, let current = self.continuedTask as? BGContinuedProcessingTask,
                      current === task else { return }
                self.continuedTask = nil
                task.setTaskCompleted(success: false)
            }
        }
    }
}
