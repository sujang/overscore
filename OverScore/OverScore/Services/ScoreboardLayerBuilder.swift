import QuartzCore
import AVFoundation
import UIKit

struct ScoreboardLayerBuilder {

    struct Config {
        let homeTeamName: String
        let awayTeamName: String
        let events: [ScoreEvent]
        let style: ScoreboardStyle
        let videoSize: CGSize
        let videoDuration: TimeInterval
        let timerSegments: [TimerSegment]
        let homeTeamColor: CGColor?
        let awayTeamColor: CGColor?
        let matchInfo: String?
        let pkKicks: [PKKick]
        let penaltyTimers: [PenaltyTimer]
        let timeouts: [TimeoutEvent]
    }

    // MARK: - Public

    static func buildOverlayLayer(config: Config) -> CALayer {
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: config.videoSize)

        // チーム名・スコア・タイマー等のスコアボード本体（試合情報のみ表示モードでは非表示）
        if config.style.showTeamsSection {
            let container = buildContainerLayer(config: config)
            overlayLayer.addSublayer(container)

            // PK overlay (positioned below main scoreboard)
            var bottomY = container.frame.maxY + config.videoSize.width * ScoreboardPreviewView.baseRatio * config.style.scale * 0.25

            if !config.pkKicks.isEmpty {
                let pkLayer = buildPKLayer(config: config, mainContainerFrame: container.frame)
                overlayLayer.addSublayer(pkLayer)
                bottomY = pkLayer.frame.maxY + config.videoSize.width * ScoreboardPreviewView.baseRatio * config.style.scale * 0.25
            }

            // Penalty timer overlay (positioned below scoreboard/PK, outside container)
            if !config.penaltyTimers.isEmpty {
                let penaltyLayer = buildPenaltyTimerLayer(config: config, originX: container.frame.origin.x, originY: bottomY)
                if let penaltyLayer {
                    overlayLayer.addSublayer(penaltyLayer)
                }
            }
        }

        // Match info (independent position & scale)
        if let info = config.matchInfo, !info.isEmpty {
            let base = config.videoSize.width * ScoreboardPreviewView.baseRatio * config.style.matchInfoScale
            let infoLayer = buildMatchInfoLayer(
                info: info,
                base: base,
                theme: config.style.theme,
                style: config.style,
                videoSize: config.videoSize
            )
            overlayLayer.addSublayer(infoLayer)
        }

        return overlayLayer
    }

    // MARK: - Container

    private static func buildContainerLayer(config: Config) -> CALayer {
        // ScoreboardPreviewView と同じ baseRatio を使用して縮尺を統一
        // Preview: base = containerWidth * baseRatio → .scaleEffect(style.scale)
        // Export:  base = videoWidth   * baseRatio * style.scale
        let base = config.videoSize.width * ScoreboardPreviewView.baseRatio * config.style.scale

        // フォントサイズ（プレビューと同じ倍率）
        let periodFontSize = base * 0.55
        let timerFontSize  = base * 0.6
        let teamFontSize   = base * 0.65
        let scoreFontSize  = base * 0.85

        // レイアウト寸法（プレビューと同じ倍率）
        let circleSize   = base * 1.4  // 高さ（円の直径）
        let maxHomeScore = config.events.filter { $0.team == .home && $0.kind == .point }.count
        let maxAwayScore = config.events.filter { $0.team == .away && $0.kind == .point }.count
        let maxScoreDigits = max(1, String(max(maxHomeScore, maxAwayScore)).count)
        let circleWidth  = maxScoreDigits <= 2 ? circleSize : circleSize + CGFloat(maxScoreDigits - 2) * base * 0.7
        let accentHeight = base * 0.125
        let gap          = base * 0.375   // メインセクション要素間隔
        let mainPaddingH = base * 0.5
        let mainPaddingV = base * 0.3125
        let cornerRadius = base * 0.375

        let theme = config.style.theme
        let showTimer = config.style.showMatchTimer
        let timerOnRight = config.style.timerPosition == .right
        let segments = config.timerSegments

        // ピリオド表記: 全セグメントのラベルから最長を基準に幅を決定
        let periodLabels = segments.compactMap { $0.periodLabel }.filter { !$0.isEmpty }
        let showPeriod = !periodLabels.isEmpty

        // ── セクション幅の計算 ──
        let periodPaddingH = base * 0.375
        let periodWidth: CGFloat
        if showPeriod {
            let maxLabelWidth = periodLabels.map { estimateTextWidth($0, fontSize: periodFontSize) }.max() ?? 0
            periodWidth = maxLabelWidth + periodPaddingH * 2
        } else {
            periodWidth = 0
        }

        let timerPaddingH = base * 0.5
        let anySegmentPlusPrefix = segments.contains { $0.showPlusPrefix }
        let timerSampleText = anySegmentPlusPrefix ? "+00:00" : "00:00"
        let timerTextWidth = estimateTextWidth(timerSampleText, fontSize: timerFontSize, monospaced: true)
        let allSegmentsPK = !segments.isEmpty && segments.allSatisfy { ($0.periodLabel ?? "").lowercased() == "pk" }
        let timerWidth: CGFloat = (showTimer && !allSegmentsPK) ? timerTextWidth + timerPaddingH * 2 : 0

        let homeTextWidth = estimateTextWidth(config.homeTeamName, fontSize: teamFontSize)
        let awayTextWidth = estimateTextWidth(config.awayTeamName, fontSize: teamFontSize)
        let teamNamePadding = teamFontSize * 2  // 2文字分の余白（片側）
        let homeAreaWidth = homeTextWidth + teamNamePadding * 2
        let awayAreaWidth = awayTextWidth + teamNamePadding * 2
        let showScore = config.style.showScore
        let vsFontSize = base * 0.6
        let vsTextWidth = estimateTextWidth("vs", fontSize: vsFontSize)
        // タイムアウト表示用の縦並びドット列（最大3つ/列）
        let timeoutDotSize: CGFloat = base * 0.3
        let timeoutDotSpacing: CGFloat = base * 0.1
        let timeoutMaxRows = 3
        let homeTOCount = config.style.showTimeouts
            ? config.timeouts.filter { $0.team == .home }.count
            : 0
        let awayTOCount = config.style.showTimeouts
            ? config.timeouts.filter { $0.team == .away }.count
            : 0
        func timeoutColumnWidth(_ count: Int) -> CGFloat {
            guard count > 0 else { return 0 }
            let cols = (count + timeoutMaxRows - 1) / timeoutMaxRows
            return CGFloat(cols) * timeoutDotSize + CGFloat(cols - 1) * timeoutDotSpacing
        }
        let homeDotColW = timeoutColumnWidth(homeTOCount)
        let awayDotColW = timeoutColumnWidth(awayTOCount)

        var mainContentWidth: CGFloat
        if showScore {
            mainContentWidth = homeAreaWidth + gap + circleWidth + gap + circleWidth + gap + awayAreaWidth
        } else {
            mainContentWidth = homeAreaWidth + gap + vsTextWidth + gap + awayAreaWidth
        }
        if homeDotColW > 0 { mainContentWidth += homeDotColW + gap }
        if awayDotColW > 0 { mainContentWidth += awayDotColW + gap }
        let mainWidth = mainContentWidth + mainPaddingH * 2

        // ── コンテナサイズ ──
        // セットカウントバッジ用に上部に余白を確保
        let setCountTopExtra: CGFloat = config.style.showSetCount ? base * 0.55 : 0
        let containerWidth = periodWidth + timerWidth + mainWidth
        let containerHeight = circleSize + mainPaddingV * 2 + setCountTopExtra

        let container = CALayer()
        container.frame = containerFrame(
            style: config.style,
            videoSize: config.videoSize,
            containerSize: CGSize(width: containerWidth, height: containerHeight)
        )

        applyThemeBackground(to: container, theme: theme, cornerRadius: cornerRadius)

        // ── Period label / Timer の配置位置を計算 ──
        // 左配置: [Period][Timer][Main]
        // 右配置: [Main][Timer][Period]
        let periodX: CGFloat
        let timerX: CGFloat
        let mainStartX: CGFloat

        if timerOnRight {
            // [Main][Timer][Period]
            mainStartX = 0
            timerX = mainWidth
            periodX = mainWidth + timerWidth
        } else {
            // [Period][Timer][Main]
            periodX = 0
            timerX = periodWidth
            mainStartX = periodWidth + timerWidth
        }

        // ── Period label section (white bg / black text) ──
        if showPeriod {
            let periodBg = CALayer()
            periodBg.frame = CGRect(x: periodX, y: setCountTopExtra, width: periodWidth, height: containerHeight - setCountTopExtra)
            periodBg.backgroundColor = UIColor.white.cgColor
            container.addSublayer(periodBg)

            let periodLabelFrame = CGRect(
                x: periodX,
                y: setCountTopExtra + (containerHeight - setCountTopExtra - periodFontSize - 4) / 2,
                width: periodWidth,
                height: periodFontSize + 4
            )

            addPeriodLabelLayers(
                to: container,
                frame: periodLabelFrame,
                segments: segments,
                duration: config.videoDuration,
                fontSize: periodFontSize
            )
        }

        // ── Timer section (inverted background) ──
        // 全セグメントPKの場合は timerWidth=0 で既にスキップ済み

        if showTimer && !allSegmentsPK {
            let timerWrapper = CALayer()
            timerWrapper.frame = CGRect(x: timerX, y: setCountTopExtra, width: timerWidth, height: containerHeight - setCountTopExtra)

            let timerBg = CALayer()
            timerBg.frame = CGRect(x: 0, y: 0, width: timerWidth, height: containerHeight - setCountTopExtra)
            timerBg.backgroundColor = textColor(for: theme)
            timerWrapper.addSublayer(timerBg)

            let timerFrame = CGRect(
                x: 0,
                y: (containerHeight - setCountTopExtra - timerFontSize - 4) / 2,
                width: timerWidth,
                height: timerFontSize + 4
            )
            addTimerLayers(
                to: timerWrapper,
                frame: timerFrame,
                duration: config.videoDuration,
                fontSize: timerFontSize,
                defaultTimerTextColor: invertedTextColor(for: theme),
                segments: segments,
                timeouts: config.timeouts
            )

            // PKセグメントが混在する場合、PK区間でタイマーを非表示
            if segments.contains(where: { ($0.periodLabel ?? "").lowercased() == "pk" }) {
                addPKHideAnimation(to: timerWrapper, segments: segments, duration: config.videoDuration)
            }

            container.addSublayer(timerWrapper)
        }

        // ── Main content area (team names + score circles) ──
        // 垂直位置の計算（バッジ余白分だけ下にシフトした中心）
        let centerY = setCountTopExtra + (containerHeight - setCountTopExtra) / 2
        let circleY = centerY - circleSize / 2

        let teamTextFrameH = teamFontSize + 4
        let vStackSpacing = base * 0.125
        let teamVStackH = teamTextFrameH + vStackSpacing + accentHeight
        let teamVStackY = centerY - teamVStackH / 2
        let accentY = teamVStackY + teamTextFrameH + vStackSpacing

        // 左から順に X 座標を進める
        var x = mainStartX + mainPaddingH

        // Home team name（左右に teamNamePadding 分の余白）
        x += teamNamePadding
        let homeLabel = makeTextLayer(
            fontSize: teamFontSize,
            alignment: .center,
            color: textColor(for: theme),
            weight: .semibold
        )
        homeLabel.string = config.homeTeamName
        homeLabel.frame = CGRect(x: x, y: teamVStackY, width: homeTextWidth, height: teamTextFrameH)
        container.addSublayer(homeLabel)

        let homeAccent = CALayer()
        homeAccent.frame = CGRect(x: x, y: accentY, width: homeTextWidth, height: accentHeight)
        let homeBaseAccent = config.homeTeamColor ?? scoreColor(for: theme)
        homeAccent.backgroundColor = accentColorAtZero(
            team: .home,
            style: config.style,
            segments: segments,
            baseColor: homeBaseAccent
        )
        if let anim = makeAccentColorAnimation(
            team: .home,
            style: config.style,
            segments: segments,
            baseColor: homeBaseAccent,
            duration: config.videoDuration
        ) {
            homeAccent.add(anim, forKey: "homeAccentColor")
        }
        container.addSublayer(homeAccent)

        x += homeTextWidth + teamNamePadding + gap

        // Home timeout dots (縦並び、最大3つ/列、チーム名とスコアの間)
        // ホーム側: 列は内側(スコア寄り)から外側(チーム名寄り)へ拡張 → 右詰め
        if homeDotColW > 0 {
            addTimeoutDotsVertical(
                to: container,
                team: .home,
                timeouts: config.timeouts,
                x: x,
                centerY: centerY,
                dotSize: timeoutDotSize,
                spacing: timeoutDotSpacing,
                maxRows: timeoutMaxRows,
                reverseColumns: true,
                duration: config.videoDuration
            )
            x += homeDotColW + gap
        }

        // セット数オーバーレイ用に、スコア丸のフレームを記録
        var homeCircleFrame: CGRect = .zero
        var awayCircleFrame: CGRect = .zero

        if showScore {
            // Home score circle
            let homeCircleWrapper = CALayer()
            homeCircleWrapper.frame = CGRect(x: x, y: circleY, width: circleWidth, height: circleSize)
            homeCircleFrame = homeCircleWrapper.frame

            let homeCircleBg = CALayer()
            homeCircleBg.frame = CGRect(x: 0, y: 0, width: circleWidth, height: circleSize)
            homeCircleBg.backgroundColor = textColor(for: theme)
            homeCircleBg.cornerRadius = circleSize / 2
            homeCircleWrapper.addSublayer(homeCircleBg)

            addScoreBackgroundFlashAnimation(
                to: homeCircleBg,
                baseColor: textColor(for: theme),
                flashColor: scoreFlashColor(for: theme),
                events: config.events,
                team: .home,
                duration: config.videoDuration
            )

            let homeScoreFrame = CGRect(
                x: 0,
                y: (circleSize - scoreFontSize - 4) / 2,
                width: circleWidth,
                height: scoreFontSize + 4
            )
            addSingleTeamScoreLayers(
                to: homeCircleWrapper,
                frame: homeScoreFrame,
                events: config.events,
                team: .home,
                duration: config.videoDuration,
                fontSize: scoreFontSize,
                textColor: invertedTextColor(for: theme),
                resetOnSetWon: config.style.showSetCount
            )

            addScorePulseAnimation(
                to: homeCircleWrapper,
                events: config.events,
                team: .home,
                duration: config.videoDuration
            )
            container.addSublayer(homeCircleWrapper)

            x += circleWidth + gap

            // Away score circle
            let awayCircleWrapper = CALayer()
            awayCircleWrapper.frame = CGRect(x: x, y: circleY, width: circleWidth, height: circleSize)
            awayCircleFrame = awayCircleWrapper.frame

            let awayCircleBg = CALayer()
            awayCircleBg.frame = CGRect(x: 0, y: 0, width: circleWidth, height: circleSize)
            awayCircleBg.backgroundColor = textColor(for: theme)
            awayCircleBg.cornerRadius = circleSize / 2
            awayCircleWrapper.addSublayer(awayCircleBg)

            addScoreBackgroundFlashAnimation(
                to: awayCircleBg,
                baseColor: textColor(for: theme),
                flashColor: scoreFlashColor(for: theme),
                events: config.events,
                team: .away,
                duration: config.videoDuration
            )

            let awayScoreFrame = CGRect(
                x: 0,
                y: (circleSize - scoreFontSize - 4) / 2,
                width: circleWidth,
                height: scoreFontSize + 4
            )
            addSingleTeamScoreLayers(
                to: awayCircleWrapper,
                frame: awayScoreFrame,
                events: config.events,
                team: .away,
                duration: config.videoDuration,
                fontSize: scoreFontSize,
                textColor: invertedTextColor(for: theme),
                resetOnSetWon: config.style.showSetCount
            )

            addScorePulseAnimation(
                to: awayCircleWrapper,
                events: config.events,
                team: .away,
                duration: config.videoDuration
            )
            container.addSublayer(awayCircleWrapper)

            x += circleWidth + gap
        } else {
            // "vs" separator
            let vsLayer = makeTextLayer(
                fontSize: vsFontSize,
                alignment: .center,
                color: textColor(for: theme),
                weight: .semibold
            )
            vsLayer.string = "vs"
            vsLayer.opacity = 0.6
            let vsFrameH = vsFontSize + 4
            vsLayer.frame = CGRect(
                x: x,
                y: centerY - vsFrameH / 2,
                width: vsTextWidth,
                height: vsFrameH
            )
            container.addSublayer(vsLayer)
            x += vsTextWidth + gap
        }

        // Away timeout dots (縦並び、スコアとチーム名の間)
        // アウェイ側: 列は内側(スコア寄り)から外側(チーム名寄り)へ拡張 → 左詰め
        if awayDotColW > 0 {
            addTimeoutDotsVertical(
                to: container,
                team: .away,
                timeouts: config.timeouts,
                x: x,
                centerY: centerY,
                dotSize: timeoutDotSize,
                spacing: timeoutDotSpacing,
                maxRows: timeoutMaxRows,
                reverseColumns: false,
                duration: config.videoDuration
            )
            x += awayDotColW + gap
        }

        // Away team name（左右に teamNamePadding 分の余白）
        x += teamNamePadding
        let awayLabel = makeTextLayer(
            fontSize: teamFontSize,
            alignment: .center,
            color: textColor(for: theme),
            weight: .semibold
        )
        awayLabel.string = config.awayTeamName
        awayLabel.frame = CGRect(x: x, y: teamVStackY, width: awayTextWidth, height: teamTextFrameH)
        container.addSublayer(awayLabel)

        let awayAccent = CALayer()
        awayAccent.frame = CGRect(x: x, y: accentY, width: awayTextWidth, height: accentHeight)
        let awayBaseAccent = config.awayTeamColor ?? scoreColor(for: theme)
        awayAccent.backgroundColor = accentColorAtZero(
            team: .away,
            style: config.style,
            segments: segments,
            baseColor: awayBaseAccent
        )
        if let anim = makeAccentColorAnimation(
            team: .away,
            style: config.style,
            segments: segments,
            baseColor: awayBaseAccent,
            duration: config.videoDuration
        ) {
            awayAccent.add(anim, forKey: "awayAccentColor")
        }
        container.addSublayer(awayAccent)

        // ── セットカウントオーバーレイ ──
        if config.style.showSetCount && showScore {
            addSetCountOverlay(
                to: container,
                circleFrame: homeCircleFrame,
                events: config.events,
                team: .home,
                duration: config.videoDuration,
                base: base
            )
            addSetCountOverlay(
                to: container,
                circleFrame: awayCircleFrame,
                events: config.events,
                team: .away,
                duration: config.videoDuration,
                base: base
            )
        }

        return container
    }

    // MARK: - Set Count Overlay

    /// スコア丸の上に小さくセット獲得数 `[N]` を表示するレイヤーを追加する。
    /// セット獲得イベントごとに opacity アニメーションで切り替わる。
    private static func addSetCountOverlay(
        to container: CALayer,
        circleFrame: CGRect,
        events: [ScoreEvent],
        team: Team,
        duration: TimeInterval,
        base: CGFloat
    ) {
        let fontSize = base * 0.4
        let labelH = fontSize + base * 0.1 * 2 + 4
        let labelW = circleFrame.width + base * 0.6
        let frame = CGRect(
            x: circleFrame.midX - labelW / 2,
            y: circleFrame.minY - labelH * 0.55,
            width: labelW,
            height: labelH
        )

        // 背景capsule（常時表示）
        let bg = CALayer()
        bg.frame = frame
        bg.backgroundColor = UIColor.black.withAlphaComponent(0.75).cgColor
        bg.cornerRadius = labelH / 2
        container.addSublayer(bg)

        // セット獲得タイムスタンプから状態列を構築
        let sorted = events
            .filter { $0.team == team && $0.kind == .setWon }
            .sorted { $0.timestamp < $1.timestamp }
        var states: [(string: String, start: Double, end: Double)] = []
        if sorted.isEmpty {
            states.append(("[0]", 0, duration))
        } else {
            states.append(("[0]", 0, sorted[0].timestamp))
            for (i, ev) in sorted.enumerated() {
                let end = (i + 1 < sorted.count) ? sorted[i + 1].timestamp : duration
                states.append(("[\(i + 1)]", ev.timestamp, end))
            }
        }

        addOpacityAnimatedTextLayers(
            to: container,
            frame: frame,
            states: states,
            duration: duration,
            fontSize: fontSize,
            textColor: UIColor.yellow.cgColor,
            fontWeight: .bold
        )
    }

    // MARK: - Section-based team accent color animation

    private static func segmentColorHex(_ seg: TimerSegment, team: Team) -> String? {
        team == .home ? seg.homeTeamColorHex : seg.awayTeamColorHex
    }

    /// セクション色オプションが有効な場合、指定時刻のチーム色（CGColor）を返す。
    /// 該当時刻に有効なセクションが無い／色設定が無ければ baseColor を使う。
    private static func accentColor(
        atVideoTime videoTime: TimeInterval,
        team: Team,
        segments: [TimerSegment],
        baseColor: CGColor
    ) -> CGColor {
        var lastHex: String? = nil
        for seg in segments {
            guard let start = seg.effectiveStartTime else { continue }
            if start <= videoTime, let hex = segmentColorHex(seg, team: team) {
                lastHex = hex
            } else if start <= videoTime {
                lastHex = nil // 該当セクションに色設定なし → 既定値に戻す
            }
        }
        if let hex = lastHex, let ui = UIColor(hex: hex) {
            return ui.cgColor
        }
        return baseColor
    }

    private static func accentColorAtZero(
        team: Team,
        style: ScoreboardStyle,
        segments: [TimerSegment],
        baseColor: CGColor
    ) -> CGColor {
        guard style.useSegmentTeamColors else { return baseColor }
        return accentColor(atVideoTime: 0, team: team, segments: segments, baseColor: baseColor)
    }

    private static func makeAccentColorAnimation(
        team: Team,
        style: ScoreboardStyle,
        segments: [TimerSegment],
        baseColor: CGColor,
        duration: TimeInterval
    ) -> CAKeyframeAnimation? {
        guard style.useSegmentTeamColors, duration > 0 else { return nil }

        // 色変化点 = 各セクションの effectiveStartTime（0 始点も含める）
        var changeTimes: [TimeInterval] = [0]
        for seg in segments {
            if let start = seg.effectiveStartTime, start > 0 {
                changeTimes.append(start)
            }
        }
        changeTimes = changeTimes.sorted()

        var keyTimes: [NSNumber] = []
        var values: [CGColor] = []
        var prev: CGColor? = nil

        for t in changeTimes {
            let c = accentColor(atVideoTime: t, team: team, segments: segments, baseColor: baseColor)
            if let p = prev, p == c { continue }
            let kt = min(t / duration, 1.0)
            keyTimes.append(NSNumber(value: kt))
            values.append(c)
            prev = c
        }
        guard values.count >= 2 else { return nil }
        keyTimes.append(1.0)
        values.append(values.last!)

        let anim = CAKeyframeAnimation(keyPath: "backgroundColor")
        anim.keyTimes = keyTimes
        anim.values = values
        anim.calculationMode = .discrete
        anim.duration = duration
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        return anim
    }

    // MARK: - Position

    private static func containerFrame(
        style: ScoreboardStyle,
        videoSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        let x = min(style.positionX * videoSize.width,
                     videoSize.width - containerSize.width)
        let y = min(style.positionY * videoSize.height,
                     videoSize.height - containerSize.height)
        return CGRect(
            origin: CGPoint(x: max(x, 0), y: max(y, 0)),
            size: containerSize
        )
    }

    // MARK: - Match Info

    private static func buildMatchInfoLayer(
        info: String,
        base: CGFloat,
        theme: ScoreboardStyle.Theme,
        style: ScoreboardStyle,
        videoSize: CGSize
    ) -> CALayer {
        let fontSize = base * 0.45
        let paddingH = base * 0.5
        let paddingV = base * 0.2
        let cornerRadius = base * 0.375

        let textWidth = estimateTextWidth(info, fontSize: fontSize)
        let layerWidth = textWidth + paddingH * 2
        let layerHeight = fontSize + 4 + paddingV * 2

        let x = min(style.matchInfoPositionX * videoSize.width,
                     videoSize.width - layerWidth)
        let y = min(style.matchInfoPositionY * videoSize.height,
                     videoSize.height - layerHeight)

        let infoContainer = CALayer()
        infoContainer.frame = CGRect(
            x: max(x, 0),
            y: max(y, 0),
            width: layerWidth,
            height: layerHeight
        )
        applyThemeBackground(to: infoContainer, theme: theme, cornerRadius: cornerRadius)

        let textLayer = makeTextLayer(
            fontSize: fontSize,
            alignment: .natural,
            color: textColor(for: theme),
            weight: .medium
        )
        textLayer.string = info
        textLayer.frame = CGRect(
            x: paddingH,
            y: paddingV,
            width: textWidth,
            height: fontSize + 4
        )
        infoContainer.addSublayer(textLayer)

        return infoContainer
    }

    // MARK: - Theme

    private static func applyThemeBackground(to layer: CALayer, theme: ScoreboardStyle.Theme, cornerRadius: CGFloat) {
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true

        switch theme {
        case .dark:
            layer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        case .light:
            layer.backgroundColor = UIColor.white.withAlphaComponent(0.8).cgColor
        case .broadcast:
            layer.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 0.85).cgColor
        case .minimal:
            layer.backgroundColor = UIColor.black.withAlphaComponent(0.4).cgColor
        }
    }

    private static func textColor(for theme: ScoreboardStyle.Theme) -> CGColor {
        switch theme {
        case .dark, .broadcast, .minimal:
            return UIColor.white.cgColor
        case .light:
            return UIColor.black.cgColor
        }
    }

    /// Inverted text color (for timer section and score circle text)
    private static func invertedTextColor(for theme: ScoreboardStyle.Theme) -> CGColor {
        switch theme {
        case .dark, .broadcast, .minimal:
            return UIColor.black.cgColor
        case .light:
            return UIColor.white.cgColor
        }
    }

    private static func scoreColor(for theme: ScoreboardStyle.Theme) -> CGColor {
        switch theme {
        case .dark:
            return UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0).cgColor
        case .light:
            return UIColor.systemBlue.cgColor
        case .broadcast:
            return UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0).cgColor
        case .minimal:
            return UIColor.white.cgColor
        }
    }

    // MARK: - Text Measurement

    private static func estimateTextWidth(_ text: String, fontSize: CGFloat, monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
            : UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return ceil(size.width)
    }

    // MARK: - Text Layers

    private static func makeTextLayer(
        fontSize: CGFloat,
        alignment: CATextLayerAlignmentMode,
        color: CGColor,
        weight: UIFont.Weight = .medium,
        monospaced: Bool = false
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.fontSize = fontSize
        if monospaced {
            let arialFontName = (weight == .bold || weight == .semibold) ? "Arial-BoldMT" : "ArialMT"
            layer.font = UIFont(name: arialFontName, size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        } else {
            layer.font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        }
        layer.foregroundColor = color
        layer.alignmentMode = alignment
        layer.contentsScale = UIScreen.main.scale
        layer.truncationMode = .end
        return layer
    }

    // MARK: - Single-Team Score Animation

    /// Creates opacity-animated text layers for one team's score.
    /// `resetOnSetWon` がtrueの場合、`.setWon` イベント時刻でスコアを0にリセットする。
    private static func addSingleTeamScoreLayers(
        to container: CALayer,
        frame: CGRect,
        events: [ScoreEvent],
        team: Team,
        duration: TimeInterval,
        fontSize: CGFloat,
        textColor: CGColor,
        resetOnSetWon: Bool = false
    ) {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var states: [(string: String, start: Double, end: Double)] = []

        // 各「スコア変化点」の時刻と新スコア値を集める
        var score = 0
        var changes: [(timestamp: Double, newScore: Int)] = []

        for event in sorted {
            if event.kind == .setWon && resetOnSetWon {
                if score != 0 {
                    score = 0
                    changes.append((event.timestamp, 0))
                }
            } else if event.kind == .point && event.team == team {
                score += 1
                changes.append((event.timestamp, score))
            }
        }

        if changes.isEmpty {
            states.append(("0", 0, duration))
        } else {
            states.append(("0", 0, changes[0].timestamp))
            for (i, ch) in changes.enumerated() {
                let end = (i + 1 < changes.count) ? changes[i + 1].timestamp : duration
                states.append(("\(ch.newScore)", ch.timestamp, end))
            }
        }

        addOpacityAnimatedTextLayers(
            to: container,
            frame: frame,
            states: states,
            duration: duration,
            fontSize: fontSize,
            textColor: textColor,
            fontWeight: .bold
        )
    }

    // MARK: - Score Pulse Animation

    /// Adds a scale pulse animation to the score circle wrapper at each goal timestamp.
    private static func addScorePulseAnimation(
        to layer: CALayer,
        events: [ScoreEvent],
        team: Team,
        duration: TimeInterval
    ) {
        let teamEvents = events.filter { $0.team == team && $0.kind == .point }.sorted { $0.timestamp < $1.timestamp }
        guard !teamEvents.isEmpty, duration > 0 else { return }

        let pulseDuration: TimeInterval = 0.3
        var keyTimes: [NSNumber] = [0.0]
        var values: [Float] = [1.0]

        for event in teamEvents {
            let startFrac = event.timestamp / duration
            let peakFrac = (event.timestamp + pulseDuration * 0.4) / duration
            let endFrac = (event.timestamp + pulseDuration) / duration

            guard startFrac < 1.0 else { continue }

            keyTimes.append(NSNumber(value: min(startFrac, 1.0)))
            values.append(1.0)
            keyTimes.append(NSNumber(value: min(peakFrac, 1.0)))
            values.append(1.2)
            keyTimes.append(NSNumber(value: min(endFrac, 1.0)))
            values.append(1.0)
        }

        if let lastTime = keyTimes.last?.doubleValue, lastTime < 1.0 {
            keyTimes.append(1.0)
            values.append(1.0)
        }

        guard keyTimes.count >= 3 else { return }

        // anchorPoint を中心に設定してスケールが中心基点になるようにする
        let bounds = layer.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(
            x: layer.frame.origin.x + bounds.width / 2,
            y: layer.frame.origin.y + bounds.height / 2
        )

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.keyTimes = keyTimes
        animation.values = values
        animation.calculationMode = .linear
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards

        layer.add(animation, forKey: "scorePulse")
    }

    // MARK: - Score Background Flash Animation

    /// 得点時にスコア円の背景色を一時的に強調色へ変化させるアニメーション
    private static func addScoreBackgroundFlashAnimation(
        to layer: CALayer,
        baseColor: CGColor,
        flashColor: CGColor,
        events: [ScoreEvent],
        team: Team,
        duration: TimeInterval
    ) {
        let teamEvents = events.filter { $0.team == team && $0.kind == .point }.sorted { $0.timestamp < $1.timestamp }
        guard !teamEvents.isEmpty, duration > 0 else { return }

        let flashDuration: TimeInterval = 1.0
        var keyTimes: [NSNumber] = [0.0]
        var values: [CGColor] = [baseColor]

        for event in teamEvents {
            let startFrac = event.timestamp / duration
            let peakFrac = (event.timestamp + flashDuration * 0.1) / duration
            let holdFrac = (event.timestamp + flashDuration * 0.7) / duration
            let endFrac = (event.timestamp + flashDuration) / duration

            guard startFrac < 1.0 else { continue }

            keyTimes.append(NSNumber(value: min(startFrac, 1.0)))
            values.append(baseColor)
            keyTimes.append(NSNumber(value: min(peakFrac, 1.0)))
            values.append(flashColor)
            keyTimes.append(NSNumber(value: min(holdFrac, 1.0)))
            values.append(flashColor)
            keyTimes.append(NSNumber(value: min(endFrac, 1.0)))
            values.append(baseColor)
        }

        if let lastTime = keyTimes.last?.doubleValue, lastTime < 1.0 {
            keyTimes.append(1.0)
            values.append(baseColor)
        }

        guard keyTimes.count >= 3 else { return }

        let animation = CAKeyframeAnimation(keyPath: "backgroundColor")
        animation.keyTimes = keyTimes
        animation.values = values
        animation.calculationMode = .linear
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards

        layer.add(animation, forKey: "scoreBgFlash")
    }

    /// 得点時の背景強調色（テーマごと）
    private static func scoreFlashColor(for theme: ScoreboardStyle.Theme) -> CGColor {
        switch theme {
        case .dark, .broadcast, .minimal:
            return UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0).cgColor
        case .light:
            return UIColor.systemOrange.cgColor
        }
    }

    // MARK: - Opacity Animation Helper

    /// Creates opacity-animated text layers from a sequence of timed states.
    private static func addOpacityAnimatedTextLayers(
        to container: CALayer,
        frame: CGRect,
        states: [(string: String, start: Double, end: Double)],
        duration: TimeInterval,
        fontSize: CGFloat,
        textColor: CGColor,
        fontWeight: UIFont.Weight = .bold
    ) {
        for state in states {
            let layer = CATextLayer()
            layer.fontSize = fontSize
            layer.font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
            layer.foregroundColor = textColor
            layer.alignmentMode = .center
            layer.contentsScale = UIScreen.main.scale
            layer.truncationMode = .end
            layer.string = state.string
            layer.frame = frame

            if states.count == 1 {
                layer.opacity = 1.0
            } else {
                layer.opacity = 0.0

                let animation = CAKeyframeAnimation(keyPath: "opacity")
                let startFraction = duration > 0 ? state.start / duration : 0
                let endFraction = duration > 0 ? state.end / duration : 1

                animation.keyTimes = [
                    0.0,
                    NSNumber(value: max(0.0, startFraction)),
                    NSNumber(value: min(1.0, endFraction)),
                    1.0,
                ] as [NSNumber]
                animation.values = [
                    Float(0.0),
                    Float(1.0),
                    Float(0.0),
                    Float(0.0),
                ] as [Float]

                if state.start == 0 {
                    animation.keyTimes = [
                        0.0,
                        NSNumber(value: min(1.0, endFraction)),
                        1.0,
                    ] as [NSNumber]
                    animation.values = [
                        Float(1.0),
                        Float(0.0),
                        Float(0.0),
                    ] as [Float]
                }

                if state.end >= duration {
                    animation.keyTimes = [
                        0.0,
                        NSNumber(value: max(0.0, startFraction)),
                        1.0,
                    ] as [NSNumber]
                    animation.values = [
                        Float(0.0),
                        Float(1.0),
                        Float(1.0),
                    ] as [Float]
                }

                if state.start == 0 && state.end >= duration {
                    animation.keyTimes = [0.0, 1.0] as [NSNumber]
                    animation.values = [Float(1.0), Float(1.0)] as [Float]
                }

                animation.calculationMode = .discrete
                animation.duration = duration
                animation.beginTime = AVCoreAnimationBeginTimeAtZero
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards

                layer.add(animation, forKey: "textOpacity")
            }

            container.addSublayer(layer)
        }
    }

    // MARK: - Timer Animation (per-digit opacity layers)

    /// Creates per-digit CATextLayers with opacity animations for reliable timer rendering
    /// in AVVideoCompositionCoreAnimationTool export pipeline.
    /// Supports multiple timer segments with independent start/stop/offset.
    private static func addTimerLayers(
        to container: CALayer,
        frame: CGRect,
        duration: TimeInterval,
        fontSize: CGFloat,
        defaultTimerTextColor: CGColor,
        segments: [TimerSegment],
        timeouts: [TimeoutEvent] = []
    ) {
        let anyPlusPrefix = segments.contains { $0.showPlusPrefix }
        let totalSeconds = Int(ceil(duration))
        guard totalSeconds > 0 else {
            let staticLabel = makeTextLayer(
                fontSize: fontSize,
                alignment: .center,
                color: defaultTimerTextColor,
                weight: .semibold,
                monospaced: true
            )
            staticLabel.string = anyPlusPrefix ? "+00:00" : "00:00"
            staticLabel.frame = frame
            container.addSublayer(staticLabel)
            return
        }

        // モノスペースフォントの実測値から文字幅を算出し、フレーム中央に配置
        // anyPlusPrefix のとき "+MM:SS"（6文字）分の幅でレイアウト
        let layoutText = anyPlusPrefix ? "+00:00" : "00:00"
        let textWidth = estimateTextWidth(layoutText, fontSize: fontSize, monospaced: true)
        let charCount = anyPlusPrefix ? 6 : 5
        let charWidth = textWidth / CGFloat(charCount)
        let textStartX = frame.origin.x + (frame.width - textWidth) / 2

        // charOffset: anyPlusPrefix のとき先頭に "+" 1文字分ずらす
        let digitOffset: CGFloat = anyPlusPrefix ? charWidth : 0

        let minuteTensX = textStartX + digitOffset
        let minuteOnesX = textStartX + digitOffset + charWidth
        let colonX      = textStartX + digitOffset + charWidth * 2
        let secondTensX = textStartX + digitOffset + charWidth * 3
        let secondOnesX = textStartX + digitOffset + charWidth * 4

        // セグメントごとの表示色タイムライン
        func colorForVideoTime(_ videoTime: TimeInterval) -> CGColor {
            var lastColor = defaultTimerTextColor
            for seg in segments {
                guard let start = seg.effectiveStartTime else { continue }
                if start <= videoTime {
                    if let hex = seg.timerColorHex,
                       let uiColor = UIColor(hex: hex) {
                        lastColor = uiColor.cgColor
                    } else {
                        lastColor = defaultTimerTextColor
                    }
                }
            }
            return lastColor
        }

        // 色アニメーション生成 (foregroundColor keyframe)
        func makeColorAnimation() -> CAKeyframeAnimation? {
            // 全セグメントのcolor変化点を収集
            var colorChangeTimes: [TimeInterval] = [0]
            for seg in segments {
                if let start = seg.effectiveStartTime, start > 0 {
                    colorChangeTimes.append(start)
                }
            }
            colorChangeTimes = colorChangeTimes.sorted()

            var keyTimes: [NSNumber] = []
            var values: [CGColor] = []
            var prevColor: CGColor? = nil

            for t in colorChangeTimes {
                let c = colorForVideoTime(t)
                if let prev = prevColor, prev == c { continue }
                let kt = duration > 0 ? t / duration : 0
                keyTimes.append(NSNumber(value: min(kt, 1.0)))
                values.append(c)
                prevColor = c
            }
            if values.count <= 1 { return nil } // 色変化なし
            keyTimes.append(1.0)
            values.append(values.last!)

            let anim = CAKeyframeAnimation(keyPath: "foregroundColor")
            anim.keyTimes = keyTimes
            anim.values = values
            anim.calculationMode = .discrete
            anim.duration = duration
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            return anim
        }

        let colorAnimation = makeColorAnimation()
        let initialColor = colorForVideoTime(0)

        // Static colon layer
        let colonLayer = makeTextLayer(
            fontSize: fontSize,
            alignment: .center,
            color: initialColor,
            weight: .semibold,
            monospaced: true
        )
        colonLayer.string = ":"
        colonLayer.frame = CGRect(x: colonX, y: frame.origin.y, width: charWidth, height: frame.height)
        colonLayer.opacity = 1.0
        if let anim = colorAnimation { colonLayer.add(anim, forKey: "foregroundColor") }
        container.addSublayer(colonLayer)

        // "+" prefix layer (anyPlusPrefix のときのみ追加)
        if anyPlusPrefix {
            let plusLayer = makeTextLayer(
                fontSize: fontSize,
                alignment: .center,
                color: initialColor,
                weight: .semibold,
                monospaced: true
            )
            plusLayer.string = "+"
            plusLayer.frame = CGRect(x: textStartX, y: frame.origin.y, width: charWidth, height: frame.height)
            plusLayer.opacity = 0.0

            // セグメントの showPlusPrefix に基づく opacity アニメーション
            var plusKeyTimes: [NSNumber] = []
            var plusValues: [Float] = []
            var prevOpacity: Float = -1

            for second in 0...totalSeconds {
                let videoTime = TimeInterval(second)
                var showPlus = false
                for seg in segments {
                    guard let start = seg.effectiveStartTime else { continue }
                    let end = seg.timerStopTime ?? duration
                    if videoTime >= start && videoTime <= end {
                        showPlus = seg.showPlusPrefix
                        break
                    } else if videoTime > end {
                        showPlus = seg.showPlusPrefix
                    }
                }
                let opacity: Float = showPlus ? 1.0 : 0.0
                if opacity != prevOpacity {
                    let kt = duration > 0 ? Double(second) / duration : 0
                    plusKeyTimes.append(NSNumber(value: min(kt, 1.0)))
                    plusValues.append(opacity)
                    prevOpacity = opacity
                }
            }
            if let lastKT = plusKeyTimes.last?.doubleValue, lastKT < 1.0 {
                plusKeyTimes.append(1.0)
                plusValues.append(plusValues.last ?? 0.0)
            }

            if plusKeyTimes.count >= 2 {
                let plusAnim = CAKeyframeAnimation(keyPath: "opacity")
                plusAnim.keyTimes = plusKeyTimes
                plusAnim.values = plusValues
                plusAnim.calculationMode = .discrete
                plusAnim.duration = duration
                plusAnim.beginTime = AVCoreAnimationBeginTimeAtZero
                plusAnim.isRemovedOnCompletion = false
                plusAnim.fillMode = .forwards
                plusLayer.add(plusAnim, forKey: "plusOpacity")
            } else {
                plusLayer.opacity = plusValues.first ?? 0.0
            }

            if let anim = colorAnimation { plusLayer.add(anim, forKey: "foregroundColor") }
            container.addSublayer(plusLayer)
        }

        func addDigitLayers(
            xPos: CGFloat,
            width: CGFloat,
            maxDigit: Int,
            digitExtractor: @escaping (Int) -> Int
        ) {
            for digit in 0...maxDigit {
                let layer = makeTextLayer(
                    fontSize: fontSize,
                    alignment: .center,
                    color: initialColor,
                    weight: .semibold,
                    monospaced: true
                )
                layer.string = "\(digit)"
                layer.frame = CGRect(x: xPos, y: frame.origin.y, width: width, height: frame.height)
                layer.opacity = 0.0

                var keyTimes: [NSNumber] = []
                var values: [Float] = []

                var previousOpacity: Float = -1

                for second in 0...totalSeconds {
                    let currentDigit = digitExtractor(second)
                    let opacity: Float = (currentDigit == digit) ? 1.0 : 0.0

                    if opacity != previousOpacity {
                        let time = duration > 0 ? Double(second) / duration : 0
                        keyTimes.append(NSNumber(value: min(time, 1.0)))
                        values.append(opacity)
                        previousOpacity = opacity
                    }
                }

                if let lastTime = keyTimes.last?.doubleValue, lastTime < 1.0 {
                    keyTimes.append(1.0)
                    values.append(values.last ?? 0.0)
                }

                guard keyTimes.count >= 2 else {
                    layer.opacity = values.first ?? 0.0
                    if let anim = colorAnimation { layer.add(anim, forKey: "foregroundColor") }
                    container.addSublayer(layer)
                    continue
                }

                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.keyTimes = keyTimes
                animation.values = values
                animation.calculationMode = .discrete
                animation.duration = duration
                animation.beginTime = AVCoreAnimationBeginTimeAtZero
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards

                layer.add(animation, forKey: "digitOpacity")
                if let anim = colorAnimation { layer.add(anim, forKey: "foregroundColor") }
                container.addSublayer(layer)
            }
        }

        /// マルチセグメント対応: 動画秒数 → 試合経過秒数
        /// effectiveStartTime〜timerStartTime の間はオフセット値（初期値）を表示
        /// timerStartTime 以降はタイマー計測を開始
        /// セグメント外の区間はフリーズ（直前セグメントの最終値を維持）
        /// タイムアウトによる累計停止秒数（from〜to の間）
        func totalPausedSeconds(from start: TimeInterval, to end: TimeInterval) -> Int {
            var paused: TimeInterval = 0
            for timeout in timeouts {
                paused += timeout.pausedSeconds(from: start, to: end)
            }
            return Int(paused)
        }

        func matchSecond(from videoSecond: Int) -> Int {
            let videoTime = TimeInterval(videoSecond)
            var lastMatchSecond = 0

            for seg in segments {
                let effStart = seg.effectiveStartTime
                guard let kickoff = seg.timerStartTime ?? effStart else { continue }
                let segStart = effStart ?? kickoff
                let stop = seg.timerStopTime ?? duration
                let offset = Int(seg.timerStartOffset ?? 0)

                if videoTime >= segStart && videoTime <= stop {
                    if videoTime < kickoff {
                        // 区切り開始〜キックオフ前: オフセット値（初期値）を表示
                        return offset
                    }
                    // キックオフ以降: タイマー計測（タイムアウト分を差し引く）
                    let elapsed = max(0, videoSecond - Int(kickoff))
                    let paused = totalPausedSeconds(from: kickoff, to: videoTime)
                    return max(0, elapsed - paused) + offset
                } else if videoTime > stop {
                    // このセグメントを通過済み → 最終値を記録
                    let elapsed = max(0, Int(stop) - Int(kickoff))
                    let paused = totalPausedSeconds(from: kickoff, to: stop)
                    lastMatchSecond = max(0, elapsed - paused) + offset
                } else {
                    break
                }
            }

            return lastMatchSecond
        }

        addDigitLayers(xPos: minuteTensX, width: charWidth, maxDigit: 9) { second in
            (matchSecond(from: second) / 60) / 10
        }

        addDigitLayers(xPos: minuteOnesX, width: charWidth, maxDigit: 9) { second in
            (matchSecond(from: second) / 60) % 10
        }

        addDigitLayers(xPos: secondTensX, width: charWidth, maxDigit: 5) { second in
            (matchSecond(from: second) % 60) / 10
        }

        addDigitLayers(xPos: secondOnesX, width: charWidth, maxDigit: 9) { second in
            (matchSecond(from: second) % 60) % 10
        }
    }

    // MARK: - Period Label Animation (multi-segment)

    /// Creates opacity-animated CATextLayers for period labels, switching based on segment time ranges.
    private static func addPeriodLabelLayers(
        to container: CALayer,
        frame: CGRect,
        segments: [TimerSegment],
        duration: TimeInterval,
        fontSize: CGFloat
    ) {
        // 各セグメントのラベルに対してテキストレイヤーを作成し、
        // そのセグメントの時間範囲でのみ表示する
        struct LabelSpan {
            let label: String
            let start: TimeInterval
            let end: TimeInterval
        }

        var spans: [LabelSpan] = []
        for (i, seg) in segments.enumerated() {
            guard let label = seg.periodLabel, !label.isEmpty else { continue }
            let start = seg.effectiveStartTime ?? 0
            // 次のセグメントの実効開始時刻、または動画終了まで
            let end: TimeInterval
            if i + 1 < segments.count, let nextStart = segments[i + 1].effectiveStartTime {
                end = nextStart
            } else {
                end = duration
            }
            spans.append(LabelSpan(label: label, start: start, end: end))
        }

        // 最初のセグメント開始前の表示: 最初のスパンのラベルを使う
        if let first = spans.first, first.start > 0 {
            spans[0] = LabelSpan(label: first.label, start: 0, end: first.end)
        }

        let states = spans.map { (string: $0.label, start: $0.start, end: $0.end) }

        addOpacityAnimatedTextLayers(
            to: container,
            frame: frame,
            states: states,
            duration: duration,
            fontSize: fontSize,
            textColor: UIColor.black.cgColor,
            fontWeight: .bold
        )
    }

    // MARK: - PK Overlay Layer

    private static func buildPKLayer(config: Config, mainContainerFrame: CGRect) -> CALayer {
        let base = config.videoSize.width * ScoreboardPreviewView.baseRatio * config.style.scale
        let teamFontSize = base * 0.5
        let markSize = base * 0.55
        let markWidth = base * 0.7
        let markSpacing = base * 0.15
        let rowSpacing = base * 0.2
        let paddingH = base * 0.4
        let paddingV = base * 0.25
        let cornerRadius = base * 0.375

        let homePK = config.pkKicks.filter { $0.team == .home }.sorted { $0.order < $1.order }
        let awayPK = config.pkKicks.filter { $0.team == .away }.sorted { $0.order < $1.order }
        let maxKicks = max(homePK.count, awayPK.count, 1)

        let teamNameWidth = max(
            estimateTextWidth(config.homeTeamName, fontSize: teamFontSize),
            estimateTextWidth(config.awayTeamName, fontSize: teamFontSize)
        )

        let marksWidth = CGFloat(maxKicks) * (markWidth + markSpacing)
        let containerWidth = paddingH + teamNameWidth + markSpacing + marksWidth + paddingH
        let rowHeight = markSize + 4
        let containerHeight = paddingV + rowHeight + rowSpacing + rowHeight + paddingV

        let gap = base * 0.25
        let containerX = mainContainerFrame.origin.x
        let containerY = mainContainerFrame.maxY + gap

        let container = CALayer()
        container.frame = CGRect(x: containerX, y: containerY, width: containerWidth, height: containerHeight)
        applyThemeBackground(to: container, theme: config.style.theme, cornerRadius: cornerRadius)

        // 先攻チームを上段に配置
        let homeFirst = config.pkKicks.firstKickingTeam == .home
        let topRowY = paddingV
        let bottomRowY = paddingV + rowHeight + rowSpacing

        // Home row
        buildPKRow(
            in: container, teamName: config.homeTeamName, kicks: homePK,
            y: homeFirst ? topRowY : bottomRowY, teamFontSize: teamFontSize, markSize: markSize,
            markWidth: markWidth, markSpacing: markSpacing, paddingH: paddingH,
            teamNameWidth: teamNameWidth, theme: config.style.theme,
            videoDuration: config.videoDuration
        )

        // Away row
        buildPKRow(
            in: container, teamName: config.awayTeamName, kicks: awayPK,
            y: homeFirst ? bottomRowY : topRowY, teamFontSize: teamFontSize,
            markSize: markSize, markWidth: markWidth, markSpacing: markSpacing,
            paddingH: paddingH, teamNameWidth: teamNameWidth,
            theme: config.style.theme, videoDuration: config.videoDuration
        )

        // PKセグメント開始時のみ表示
        addPKShowAnimation(to: container, segments: config.timerSegments, duration: config.videoDuration)

        return container
    }

    private static func buildPKRow(
        in container: CALayer,
        teamName: String,
        kicks: [PKKick],
        y: CGFloat,
        teamFontSize: CGFloat,
        markSize: CGFloat,
        markWidth: CGFloat,
        markSpacing: CGFloat,
        paddingH: CGFloat,
        teamNameWidth: CGFloat,
        theme: ScoreboardStyle.Theme,
        videoDuration: TimeInterval
    ) {
        let nameLayer = makeTextLayer(
            fontSize: teamFontSize, alignment: .natural,
            color: textColor(for: theme), weight: .semibold
        )
        nameLayer.string = teamName
        nameLayer.frame = CGRect(x: paddingH, y: y, width: teamNameWidth, height: markSize + 4)
        container.addSublayer(nameLayer)

        for (i, kick) in kicks.enumerated() {
            let x = paddingH + teamNameWidth + markSpacing + CGFloat(i) * (markWidth + markSpacing)
            let markText = kick.isGoal ? "◯" : "✗"
            let markColor = kick.isGoal
                ? UIColor.systemGreen.cgColor
                : UIColor.systemRed.cgColor

            let markLayer = makeTextLayer(
                fontSize: markSize, alignment: .center,
                color: markColor, weight: .bold
            )
            markLayer.string = markText
            markLayer.frame = CGRect(x: x, y: y, width: markWidth, height: markSize + 4)
            markLayer.opacity = 0

            let fraction = videoDuration > 0 ? kick.timestamp / videoDuration : 0
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.keyTimes = [0.0, NSNumber(value: max(0, fraction)), 1.0]
            animation.values = [Float(0), Float(1), Float(1)] as [Float]
            animation.calculationMode = .discrete
            animation.duration = videoDuration
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            markLayer.add(animation, forKey: "markAppear")

            container.addSublayer(markLayer)
        }
    }

    /// PKセグメント中のみPKオーバーレイを表示するアニメーション
    private static func addPKShowAnimation(
        to layer: CALayer,
        segments: [TimerSegment],
        duration: TimeInterval
    ) {
        guard duration > 0, !segments.isEmpty else { return }

        struct Span {
            let start: TimeInterval
            let end: TimeInterval
            let isPK: Bool
        }

        var spans: [Span] = []
        for (i, seg) in segments.enumerated() {
            let start = seg.effectiveStartTime ?? 0
            let end: TimeInterval
            if i + 1 < segments.count, let nextStart = segments[i + 1].effectiveStartTime {
                end = nextStart
            } else {
                end = duration
            }
            let isPK = (seg.periodLabel ?? "").lowercased() == "pk"
            spans.append(Span(start: start, end: end, isPK: isPK))
        }

        if spans[0].start > 0 {
            spans[0] = Span(start: 0, end: spans[0].end, isPK: spans[0].isPK)
        }

        var keyTimes: [NSNumber] = []
        var values: [Float] = []

        for span in spans {
            let startFrac = span.start / duration
            keyTimes.append(NSNumber(value: min(startFrac, 1.0)))
            values.append(span.isPK ? 1.0 : 0.0)
        }

        if let lastTime = keyTimes.last?.doubleValue, lastTime < 1.0 {
            keyTimes.append(1.0)
            values.append(values.last ?? 0.0)
        }

        guard keyTimes.count >= 2 else { return }

        layer.opacity = 0
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.keyTimes = keyTimes
        animation.values = values
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        layer.add(animation, forKey: "pkShow")
    }

    // MARK: - Timeout Dots

    /// チーム名の横にタイムアウト回数ドットを配置（opacityアニメーション付き）
    private static func addTimeoutDots(
        to container: CALayer,
        team: Team,
        timeouts: [TimeoutEvent],
        x: CGFloat,
        centerY: CGFloat,
        dotSize: CGFloat,
        spacing: CGFloat,
        duration: TimeInterval
    ) {
        let teamTimeouts = timeouts
            .filter { $0.team == team }
            .sorted { $0.timestamp < $1.timestamp }
        guard !teamTimeouts.isEmpty else { return }

        let totalSeconds = Int(ceil(duration))
        guard totalSeconds > 0 else { return }

        for (i, timeout) in teamTimeouts.enumerated() {
            let dotX = x + CGFloat(i) * (dotSize + spacing)
            let dotY = centerY - dotSize / 2

            let dot = CALayer()
            dot.frame = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.backgroundColor = UIColor.yellow.cgColor
            dot.opacity = 0.0

            // タイムアウト開始時に出現
            let startT = duration > 0 ? timeout.timestamp / duration : 0
            var keyTimes: [NSNumber] = []
            var values: [Float] = []

            if startT > 0 {
                keyTimes.append(0.0)
                values.append(0.0)
            }
            keyTimes.append(NSNumber(value: min(startT, 1.0)))
            values.append(1.0)
            keyTimes.append(1.0)
            values.append(1.0)

            if keyTimes.count >= 2 {
                let anim = CAKeyframeAnimation(keyPath: "opacity")
                anim.keyTimes = keyTimes
                anim.values = values
                anim.calculationMode = .discrete
                anim.duration = duration
                anim.beginTime = AVCoreAnimationBeginTimeAtZero
                anim.isRemovedOnCompletion = false
                anim.fillMode = .forwards
                dot.add(anim, forKey: "dotOpacity")
            }

            container.addSublayer(dot)
        }
    }

    /// タイムアウト回数を縦並び（最大 maxRows 個/列、列を追加して展開）で表示
    /// - reverseColumns: true の場合、列は右→左へ拡張（ホーム側用）
    private static func addTimeoutDotsVertical(
        to container: CALayer,
        team: Team,
        timeouts: [TimeoutEvent],
        x: CGFloat,
        centerY: CGFloat,
        dotSize: CGFloat,
        spacing: CGFloat,
        maxRows: Int,
        reverseColumns: Bool = false,
        duration: TimeInterval
    ) {
        let teamTimeouts = timeouts
            .filter { $0.team == team }
            .sorted { $0.timestamp < $1.timestamp }
        guard !teamTimeouts.isEmpty, duration > 0 else { return }

        // 1つでも上から並ぶように、高さは常に maxRows 分確保
        let columnHeight = CGFloat(maxRows) * dotSize + CGFloat(maxRows - 1) * spacing
        let topY = centerY - columnHeight / 2
        let totalCols = (teamTimeouts.count + maxRows - 1) / maxRows

        let inactiveColor = UIColor.yellow.cgColor
        let activeColor = UIColor.systemRed.cgColor

        for (i, timeout) in teamTimeouts.enumerated() {
            let logicalCol = i / maxRows
            let row = i % maxRows
            let visualCol = reverseColumns ? (totalCols - 1 - logicalCol) : logicalCol
            let dotX = x + CGFloat(visualCol) * (dotSize + spacing)
            let dotY = topY + CGFloat(row) * (dotSize + spacing)

            let dot = CALayer()
            dot.frame = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.backgroundColor = inactiveColor
            dot.opacity = 0.0

            // opacity: タイムアウト開始時に出現
            let startT = timeout.timestamp / duration
            var opKeyTimes: [NSNumber] = []
            var opValues: [Float] = []
            if startT > 0 {
                opKeyTimes.append(0.0)
                opValues.append(0.0)
            }
            opKeyTimes.append(NSNumber(value: min(startT, 1.0)))
            opValues.append(1.0)
            opKeyTimes.append(1.0)
            opValues.append(1.0)

            if opKeyTimes.count >= 2 {
                let anim = CAKeyframeAnimation(keyPath: "opacity")
                anim.keyTimes = opKeyTimes
                anim.values = opValues
                anim.calculationMode = .discrete
                anim.duration = duration
                anim.beginTime = AVCoreAnimationBeginTimeAtZero
                anim.isRemovedOnCompletion = false
                anim.fillMode = .forwards
                dot.add(anim, forKey: "dotOpacity")
            }

            // backgroundColor: アクティブ区間だけ強調色
            let activeStart = timeout.timestamp / duration
            let activeEnd: Double = {
                if let end = timeout.endTimestamp {
                    return min(end / duration, 1.0)
                }
                return 1.0
            }()
            if activeStart < 1.0, activeEnd > activeStart {
                var bgKeyTimes: [NSNumber] = [0.0]
                var bgValues: [CGColor] = [inactiveColor]
                bgKeyTimes.append(NSNumber(value: min(activeStart, 1.0)))
                bgValues.append(activeColor)
                if activeEnd < 1.0 {
                    bgKeyTimes.append(NSNumber(value: activeEnd))
                    bgValues.append(inactiveColor)
                    bgKeyTimes.append(1.0)
                    bgValues.append(inactiveColor)
                } else {
                    bgKeyTimes.append(1.0)
                    bgValues.append(activeColor)
                }
                let bgAnim = CAKeyframeAnimation(keyPath: "backgroundColor")
                bgAnim.keyTimes = bgKeyTimes
                bgAnim.values = bgValues
                bgAnim.calculationMode = .discrete
                bgAnim.duration = duration
                bgAnim.beginTime = AVCoreAnimationBeginTimeAtZero
                bgAnim.isRemovedOnCompletion = false
                bgAnim.fillMode = .forwards
                dot.add(bgAnim, forKey: "dotBgColor")
            }

            container.addSublayer(dot)
        }
    }

    // MARK: - Penalty Timer Layer (outside scoreboard)

    /// スコアボードの下にペナルティタイマーを横並びで配置するレイヤーを構築
    private static func buildPenaltyTimerLayer(config: Config, originX: CGFloat, originY: CGFloat) -> CALayer? {
        let penaltyTimers = config.penaltyTimers
        guard !penaltyTimers.isEmpty else { return nil }

        let base = config.videoSize.width * ScoreboardPreviewView.baseRatio * config.style.scale
        let fontSize = base * 0.45
        let rowH = fontSize + 4
        let spacing = base * 0.2
        let cornerRadius = base * 0.375
        let theme = config.style.theme
        let totalSeconds = Int(ceil(config.videoDuration))
        guard totalSeconds > 0 else { return nil }

        let homeTimers = penaltyTimers.filter { $0.team == .home }.sorted { $0.timestamp < $1.timestamp }
        let awayTimers = penaltyTimers.filter { $0.team == .away }.sorted { $0.timestamp < $1.timestamp }

        // チーム名テキスト幅
        let teamFontSize = fontSize
        let homeNameW = estimateTextWidth(config.homeTeamName, fontSize: teamFontSize) + 4
        let awayNameW = estimateTextWidth(config.awayTeamName, fontSize: teamFontSize) + 4
        let countdownW = estimateTextWidth("0:00", fontSize: fontSize, monospaced: true)
        let paddingH = base * 0.4
        let paddingV = base * 0.2

        // レイアウト幅計算
        let homeBlockW = homeTimers.isEmpty ? 0 : homeNameW + spacing + CGFloat(homeTimers.count) * (countdownW + spacing)
        let awayBlockW = awayTimers.isEmpty ? 0 : awayNameW + spacing + CGFloat(awayTimers.count) * (countdownW + spacing)
        let totalGap = (homeBlockW > 0 && awayBlockW > 0) ? base * 0.5 : 0
        let contentW = homeBlockW + totalGap + awayBlockW
        let layerW = contentW + paddingH * 2
        let layerH = rowH + paddingV * 2

        let container = CALayer()
        container.frame = CGRect(x: originX, y: originY, width: layerW, height: layerH)
        applyThemeBackground(to: container, theme: theme, cornerRadius: cornerRadius)
        container.opacity = 0.0 // 少なくとも1つアクティブなときのみ表示

        // 全体の表示/非表示アニメーション
        var visKeyTimes: [NSNumber] = []
        var visValues: [Float] = []
        var prevVis: Float = -1
        for second in 0...totalSeconds {
            let vt = TimeInterval(second)
            let anyActive = penaltyTimers.contains { $0.remainingSeconds(at: vt, timeouts: config.timeouts) != nil }
            let vis: Float = anyActive ? 1.0 : 0.0
            if vis != prevVis {
                let kt = config.videoDuration > 0 ? Double(second) / config.videoDuration : 0
                visKeyTimes.append(NSNumber(value: min(kt, 1.0)))
                visValues.append(vis)
                prevVis = vis
            }
        }
        if let last = visKeyTimes.last?.doubleValue, last < 1.0 {
            visKeyTimes.append(1.0)
            visValues.append(0.0)
        }
        if visKeyTimes.count >= 2 {
            let visAnim = CAKeyframeAnimation(keyPath: "opacity")
            visAnim.keyTimes = visKeyTimes
            visAnim.values = visValues
            visAnim.calculationMode = .discrete
            visAnim.duration = config.videoDuration
            visAnim.beginTime = AVCoreAnimationBeginTimeAtZero
            visAnim.isRemovedOnCompletion = false
            visAnim.fillMode = .forwards
            container.add(visAnim, forKey: "penaltyContainerVis")
        }

        var xPos = paddingH

        // Home チーム名 + カウントダウン
        if !homeTimers.isEmpty {
            let nameLayer = makeTextLayer(fontSize: teamFontSize, alignment: .center, color: textColor(for: theme), weight: .semibold)
            nameLayer.string = config.homeTeamName
            nameLayer.frame = CGRect(x: xPos, y: paddingV, width: homeNameW, height: rowH)
            container.addSublayer(nameLayer)
            xPos += homeNameW + spacing

            for timer in homeTimers {
                addPenaltyTimerLayers(
                    to: container,
                    penaltyTimers: [timer],
                    team: .home,
                    xCenter: xPos + countdownW / 2,
                    yStart: paddingV,
                    fontSize: fontSize,
                    rowHeight: rowH,
                    spacing: 0,
                    videoDuration: config.videoDuration,
                    timeouts: config.timeouts
                )
                xPos += countdownW + spacing
            }
        }

        xPos += (homeBlockW > 0 && awayBlockW > 0) ? base * 0.5 : 0

        // Away チーム名 + カウントダウン
        if !awayTimers.isEmpty {
            let nameLayer = makeTextLayer(fontSize: teamFontSize, alignment: .center, color: textColor(for: theme), weight: .semibold)
            nameLayer.string = config.awayTeamName
            nameLayer.frame = CGRect(x: xPos, y: paddingV, width: awayNameW, height: rowH)
            container.addSublayer(nameLayer)
            xPos += awayNameW + spacing

            for timer in awayTimers {
                addPenaltyTimerLayers(
                    to: container,
                    penaltyTimers: [timer],
                    team: .away,
                    xCenter: xPos + countdownW / 2,
                    yStart: paddingV,
                    fontSize: fontSize,
                    rowHeight: rowH,
                    spacing: 0,
                    videoDuration: config.videoDuration,
                    timeouts: config.timeouts
                )
                xPos += countdownW + spacing
            }
        }

        return container
    }

    // MARK: - Penalty Timer Digit Layers

    /// 個別ペナルティタイマーのカウントダウン桁レイヤー
    private static func addPenaltyTimerLayers(
        to container: CALayer,
        penaltyTimers: [PenaltyTimer],
        team: Team,
        xCenter: CGFloat,
        yStart: CGFloat,
        fontSize: CGFloat,
        rowHeight: CGFloat,
        spacing: CGFloat,
        videoDuration: TimeInterval,
        timeouts: [TimeoutEvent] = []
    ) {
        let teamTimers = penaltyTimers
            .filter { $0.team == team }
            .sorted { $0.timestamp < $1.timestamp }
        guard !teamTimers.isEmpty else { return }

        let totalSeconds = Int(ceil(videoDuration))
        guard totalSeconds > 0 else { return }

        // "M:SS" 表示幅を算出
        let sampleText = "0:00"
        let textWidth = estimateTextWidth(sampleText, fontSize: fontSize, monospaced: true)

        for (slotIndex, timer) in teamTimers.enumerated() {
            let y = yStart + CGFloat(slotIndex) * (rowHeight + spacing)
            let timerWrapper = CALayer()
            timerWrapper.frame = CGRect(
                x: xCenter - textWidth / 2,
                y: y,
                width: textWidth,
                height: rowHeight
            )
            timerWrapper.opacity = 0.0

            // Wrapper の表示/非表示 opacity アニメーション
            let startSec = Int(timer.timestamp)
            let endSec = Int(ceil(timer.effectiveExpiresAt(timeouts: timeouts)))

            var wrapKeyTimes: [NSNumber] = []
            var wrapValues: [Float] = []

            if startSec > 0 {
                wrapKeyTimes.append(0.0)
                wrapValues.append(0.0)
            }
            let startT = videoDuration > 0 ? Double(startSec) / videoDuration : 0
            wrapKeyTimes.append(NSNumber(value: min(startT, 1.0)))
            wrapValues.append(1.0)

            let endT = videoDuration > 0 ? Double(endSec) / videoDuration : 1
            if endT < 1.0 {
                wrapKeyTimes.append(NSNumber(value: endT))
                wrapValues.append(0.0)
            }
            wrapKeyTimes.append(1.0)
            wrapValues.append(0.0)

            if wrapKeyTimes.count >= 2 {
                let wrapAnim = CAKeyframeAnimation(keyPath: "opacity")
                wrapAnim.keyTimes = wrapKeyTimes
                wrapAnim.values = wrapValues
                wrapAnim.calculationMode = .discrete
                wrapAnim.duration = videoDuration
                wrapAnim.beginTime = AVCoreAnimationBeginTimeAtZero
                wrapAnim.isRemovedOnCompletion = false
                wrapAnim.fillMode = .forwards
                timerWrapper.add(wrapAnim, forKey: "penaltyVisibility")
            }

            // カウントダウン桁レイヤー (M:SS)
            let charWidth = textWidth / CGFloat(sampleText.count)

            func remainingSec(at videoSecond: Int) -> Int {
                let vt = TimeInterval(videoSecond)
                guard let r = timer.remainingSeconds(at: vt, timeouts: timeouts) else { return 0 }
                return Int(ceil(r))
            }

            let minuteX: CGFloat = 0
            let colonX = charWidth
            let secTensX = charWidth * 2
            let secOnesX = charWidth * 3

            let yellowColor = UIColor.yellow.cgColor

            // コロン
            let colonLayer = makeTextLayer(fontSize: fontSize, alignment: .center, color: yellowColor, weight: .semibold, monospaced: true)
            colonLayer.string = ":"
            colonLayer.frame = CGRect(x: colonX, y: 0, width: charWidth, height: rowHeight)
            timerWrapper.addSublayer(colonLayer)

            // 分（0-9）
            addCountdownDigitLayers(to: timerWrapper, xPos: minuteX, width: charWidth, height: rowHeight, maxDigit: 9, fontSize: fontSize, color: yellowColor, totalSeconds: totalSeconds, videoDuration: videoDuration) { sec in
                remainingSec(at: sec) / 60
            }

            // 秒十の位（0-5）
            addCountdownDigitLayers(to: timerWrapper, xPos: secTensX, width: charWidth, height: rowHeight, maxDigit: 5, fontSize: fontSize, color: yellowColor, totalSeconds: totalSeconds, videoDuration: videoDuration) { sec in
                (remainingSec(at: sec) % 60) / 10
            }

            // 秒一の位（0-9）
            addCountdownDigitLayers(to: timerWrapper, xPos: secOnesX, width: charWidth, height: rowHeight, maxDigit: 9, fontSize: fontSize, color: yellowColor, totalSeconds: totalSeconds, videoDuration: videoDuration) { sec in
                (remainingSec(at: sec) % 60) % 10
            }

            container.addSublayer(timerWrapper)
        }
    }

    private static func addCountdownDigitLayers(
        to container: CALayer,
        xPos: CGFloat,
        width: CGFloat,
        height: CGFloat,
        maxDigit: Int,
        fontSize: CGFloat,
        color: CGColor,
        totalSeconds: Int,
        videoDuration: TimeInterval,
        digitExtractor: (Int) -> Int
    ) {
        for digit in 0...maxDigit {
            let layer = makeTextLayer(fontSize: fontSize, alignment: .center, color: color, weight: .semibold, monospaced: true)
            layer.string = "\(digit)"
            layer.frame = CGRect(x: xPos, y: 0, width: width, height: height)
            layer.opacity = 0.0

            var keyTimes: [NSNumber] = []
            var values: [Float] = []
            var prevOpacity: Float = -1

            for second in 0...totalSeconds {
                let d = digitExtractor(second)
                let opacity: Float = (d == digit) ? 1.0 : 0.0
                if opacity != prevOpacity {
                    let t = videoDuration > 0 ? Double(second) / videoDuration : 0
                    keyTimes.append(NSNumber(value: min(t, 1.0)))
                    values.append(opacity)
                    prevOpacity = opacity
                }
            }

            if let lastKT = keyTimes.last?.doubleValue, lastKT < 1.0 {
                keyTimes.append(1.0)
                values.append(values.last ?? 0.0)
            }

            guard keyTimes.count >= 2 else {
                layer.opacity = values.first ?? 0.0
                container.addSublayer(layer)
                continue
            }

            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.keyTimes = keyTimes
            anim.values = values
            anim.calculationMode = .discrete
            anim.duration = videoDuration
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            layer.add(anim, forKey: "digitOpacity")
            container.addSublayer(layer)
        }
    }

    // MARK: - PK Hide Animation

    /// PKセグメント中はタイマーセクション全体を非表示にするopacityアニメーションを追加
    private static func addPKHideAnimation(
        to layer: CALayer,
        segments: [TimerSegment],
        duration: TimeInterval
    ) {
        guard duration > 0, !segments.isEmpty else { return }

        struct Span {
            let start: TimeInterval
            let end: TimeInterval
            let isPK: Bool
        }

        var spans: [Span] = []
        for (i, seg) in segments.enumerated() {
            let start = seg.effectiveStartTime ?? 0
            let end: TimeInterval
            if i + 1 < segments.count, let nextStart = segments[i + 1].effectiveStartTime {
                end = nextStart
            } else {
                end = duration
            }
            let isPK = (seg.periodLabel ?? "").lowercased() == "pk"
            spans.append(Span(start: start, end: end, isPK: isPK))
        }

        // 最初のスパン開始前は最初のスパンの状態を使う
        if spans[0].start > 0 {
            spans[0] = Span(start: 0, end: spans[0].end, isPK: spans[0].isPK)
        }

        var keyTimes: [NSNumber] = []
        var values: [Float] = []

        for span in spans {
            let startFrac = span.start / duration
            keyTimes.append(NSNumber(value: min(startFrac, 1.0)))
            values.append(span.isPK ? 0.0 : 1.0)
        }

        if let lastTime = keyTimes.last?.doubleValue, lastTime < 1.0 {
            keyTimes.append(1.0)
            values.append(values.last ?? 1.0)
        }

        guard keyTimes.count >= 2 else { return }

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.keyTimes = keyTimes
        animation.values = values
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards

        layer.add(animation, forKey: "pkHideTimer")
    }
}

// MARK: - UIColor hex helper (ScoreboardLayerBuilder 用)

private extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8)  & 0xFF) / 255,
            blue:  CGFloat(value         & 0xFF) / 255,
            alpha: 1
        )
    }
}
