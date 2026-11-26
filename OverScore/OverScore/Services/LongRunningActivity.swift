import UIKit

/// 動画の取り込みなど、時間のかかる処理の間だけ端末の自動ロックを止め、
/// バックグラウンドへ移ったときの実行猶予を確保する。
///
/// 自動ロックが掛かるとアプリはバックグラウンドへ移り、数秒で一時停止される。
/// 写真ライブラリからの数GBの取り込みがその途中で止まると、復帰後に失敗したり
/// システムに終了させられたりするため、取り込み中は自動ロックそのものを防ぐ。
///
/// 手動でロック・アプリ切り替えされた場合はバックグラウンドタスクで猶予を得る。
/// 猶予切れ時は必ず endBackgroundTask する（終了しないとシステムに強制終了される）。
///
/// 既知の制約（v1.3.9 時点、iOS 27.2 実機で確認）:
/// 写真ピッカーからの受け取り中に手動ロックなどで猶予（約30秒）が切れると、アプリは強制終了される
/// （RunningBoard 0x2182BAAD）。PhotosPicker が内部で PhotosFileProvider のファイルコーディネーション
/// クレームを保持しており、一時停止時にその解放待ちがタイムアウトするため。
/// 次の対策はいずれも効果がなかった:
/// - loadTransferable が返す Progress の cancel()（クレームは解放されない）
/// - iOS 26 の BGContinuedProcessingTask（タスク動作中でも猶予切れで一時停止される）
/// 防ぐには PHAssetResourceManager で直接読み出すなど、受け取り方式の変更が必要。
@MainActor
final class LongRunningActivity {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isActive = false

    /// 同時に実行中の処理の数。最後の処理が終わったときだけ自動ロックを戻す。
    private static var activeCount = 0

    static func begin(name: String) -> LongRunningActivity {
        let activity = LongRunningActivity()
        activity.start(name: name)
        return activity
    }

    private func start(name: String) {
        isActive = true
        Self.activeCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.endBackgroundTask()
            }
        }
    }

    func end() {
        guard isActive else { return }
        isActive = false
        Self.activeCount -= 1
        if Self.activeCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
