import UIKit
import os

/// 動画の取り込みなど、時間のかかる処理を端末のロックやアプリ切り替えから守る。
///
/// 1. 自動ロックを止める（画面を点けたままにする）
/// 2. 手動でロックしたり他のアプリへ切り替えたりしたときは、`beginBackgroundTask` で数十秒の猶予を得る
/// 3. 猶予が切れたら、`setCancellable` で登録した転送をアプリが一時停止される前に中断する
///
/// 3 が必要な理由: 写真ライブラリからの受け取り中はファイルコーディネーションのクレームを保持している。
/// クレームを保持したまま一時停止されると、システムが解放を待ちきれずにアプリを強制終了する
/// （RunningBoard 0x2182BAAD）。先に転送を中断すれば、強制終了ではなく通常の一時停止になり、
/// 入力中の画面も残る。
///
/// iOS 26 の BGContinuedProcessingTask も試したが、実機（iOS 27.2）ではタスクが動作中でも
/// 猶予切れでアプリが一時停止され、強制終了を防げなかったため使っていない。
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

    /// 一時停止前に中断する転送
    private var cancellable: Progress?
    /// 実行猶予がなくなり、転送を中断したか
    private(set) var wasInterrupted = false

    /// - Parameter name: デバッグ用のタスク名
    static func begin(name: String) -> LongRunningActivity {
        let activity = LongRunningActivity()
        activity.start(name: name)
        return activity
    }

    private func start(name: String) {
        isActive = true
        Self.activeCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
        // 期限切れハンドラはメインスレッドで呼ばれる
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.backgroundTaskDidExpire()
            }
        }
    }

    /// 実行猶予がなくなったときに中断する転送を登録する。nil で解除。
    func setCancellable(_ progress: Progress?) {
        // 開始通知は MainActor へ非同期に届くため、転送がすでに終わっていれば登録しない
        if let progress, progress.isFinished || progress.isCancelled { return }
        cancellable = progress
        if wasInterrupted {
            progress?.cancel()
        }
    }

    /// 猶予切れの直後にアプリは一時停止される。その前に転送を中断してクレームを手放す。
    private func backgroundTaskDidExpire() {
        endBackgroundTask()
        guard isActive else { return }
        wasInterrupted = true
        Self.logger.notice("background task expired; interrupting transfer (cancellable=\(self.cancellable != nil, privacy: .public))")
        cancellable?.cancel()
    }

    /// 処理の終了を伝える。複数回呼んでも安全。
    func end() {
        guard isActive else { return }
        isActive = false
        Self.activeCount -= 1
        if Self.activeCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        cancellable = nil
        endBackgroundTask()
        Self.logger.notice("activity ended interrupted=\(self.wasInterrupted, privacy: .public)")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
