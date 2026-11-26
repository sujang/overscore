import SwiftUI

struct ScoreboardStyleSheet: View {
    @Bindable var match: Match
    @Environment(\.dismiss) private var dismiss
    @State private var style: ScoreboardStyle
    @State private var thumbnail: UIImage?
    @State private var videoAspectRatio: CGFloat
    @State private var homeTeamNameEdit: String
    @State private var awayTeamNameEdit: String
    /// 試合情報の編集値。他の項目と同様にステージングし「保存」時のみ match に反映する
    @State private var matchInfoEdit: String
    var onSave: (() -> Void)?

    // 編集対象
    enum EditTarget: CaseIterable {
        case scoreboard
        case matchInfo

        var displayName: LocalizedStringKey {
            switch self {
            case .scoreboard: return "スコアボード"
            case .matchInfo: return "試合情報"
            }
        }
    }
    @State private var editTarget: EditTarget = .scoreboard
    @State private var showDiscardConfirm = false
    @State private var teamPresets = TeamPresetStore.load()
    @State private var showPresetPicker = false

    // ジェスチャー用ベース値（スコアボード）
    @State private var baseScale: CGFloat = 1.0
    @State private var basePosition: CGPoint = .zero

    // ジェスチャー用ベース値（試合情報）
    @State private var baseMatchInfoScale: CGFloat = 1.0
    @State private var baseMatchInfoPosition: CGPoint = .zero

    init(match: Match, thumbnail: UIImage? = nil, videoAspectRatio: CGFloat = 16.0 / 9.0, onSave: (() -> Void)? = nil) {
        self.match = match
        self._thumbnail = State(initialValue: thumbnail)
        self._videoAspectRatio = State(initialValue: videoAspectRatio)
        self.onSave = onSave
        let s = match.scoreboardStyle
        self._style = State(initialValue: s)
        self._baseScale = State(initialValue: s.scale)
        self._basePosition = State(initialValue: CGPoint(x: s.positionX, y: s.positionY))
        self._baseMatchInfoScale = State(initialValue: s.matchInfoScale)
        self._baseMatchInfoPosition = State(initialValue: CGPoint(x: s.matchInfoPositionX, y: s.matchInfoPositionY))
        self._homeTeamNameEdit = State(initialValue: match.homeTeamName)
        self._awayTeamNameEdit = State(initialValue: match.awayTeamName)
        self._matchInfoEdit = State(initialValue: match.matchInfo ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GeometryReader { geo in
                        ScoreboardPreviewView(
                            homeTeamName: homeTeamNameEdit.isEmpty ? match.homeTeamName : homeTeamNameEdit,
                            awayTeamName: awayTeamNameEdit.isEmpty ? match.awayTeamName : awayTeamNameEdit,
                            homeScore: match.homeScore,
                            awayScore: match.awayScore,
                            style: style,
                            currentPeriodLabel: match.timerSegments.first?.periodLabel,
                            matchInfo: matchInfoEdit.isEmpty ? nil : matchInfoEdit,
                            pkKicks: match.pkKicks,
                            thumbnail: thumbnail,
                            videoAspectRatio: videoAspectRatio,
                            homeSetCount: match.homeSetCount,
                            awaySetCount: match.awaySetCount
                        )
                        .simultaneousGesture(dragGesture(in: geo.size))
                        .simultaneousGesture(magnificationGesture)
                    }
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("プレビュー")
                } footer: {
                    VStack(spacing: 8) {
                        Picker("編集対象", selection: $editTarget) {
                            ForEach(EditTarget.allCases, id: \.self) { target in
                                Text(target.displayName).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("ピンチでサイズ変更・ドラッグで位置調整")
                                .font(.caption)
                            Spacer()
                            Button("リセット") {
                                if editTarget == .scoreboard {
                                    style.positionX = 0.02
                                    style.positionY = 0.02
                                    style.scale = 0.5
                                    baseScale = 0.5
                                    basePosition = CGPoint(x: 0.02, y: 0.02)
                                } else {
                                    style.matchInfoPositionX = 0.70
                                    style.matchInfoPositionY = 0.02
                                    style.matchInfoScale = 1.0
                                    baseMatchInfoScale = 1.0
                                    baseMatchInfoPosition = CGPoint(x: 0.70, y: 0.02)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                Section("テーマ") {
                    Picker("テーマ", selection: $style.theme) {
                        ForEach(ScoreboardStyle.Theme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("チーム名") {
                    TextField("ホームチーム名", text: $homeTeamNameEdit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !teamPresets.isEmpty {
                        Button {
                            showPresetPicker = true
                        } label: {
                            Label("ホームを過去のチームから選ぶ", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    TextField("アウェイチーム名", text: $awayTeamNameEdit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    ColorPicker(
                        "ホーム: \(homeTeamNameEdit.isEmpty ? match.homeTeamName : homeTeamNameEdit)",
                        selection: homeColorBinding,
                        supportsOpacity: false
                    )
                    ColorPicker(
                        "アウェイ: \(awayTeamNameEdit.isEmpty ? match.awayTeamName : awayTeamNameEdit)",
                        selection: awayColorBinding,
                        supportsOpacity: false
                    )
                    if style.homeTeamColorHex != nil || style.awayTeamColorHex != nil {
                        Button("デフォルトに戻す") {
                            style.homeTeamColorHex = nil
                            style.awayTeamColorHex = nil
                        }
                    }
                    Toggle("セクションごとに変更する", isOn: $style.useSegmentTeamColors)
                } header: {
                    Text("チームカラー")
                } footer: {
                    if style.useSegmentTeamColors {
                        Text("セクションごとの色はスコア記録画面の各セグメント設定で変更できます。未設定のセクションはここの基本色を使用します。")
                    }
                }

                Section {
                    TextField("大会名・日程など", text: $matchInfoEdit)
                } header: {
                    Text("試合情報")
                } footer: {
                    Text("スコアボード下部に表示されます")
                }

                Section {
                    Toggle("スコアボードを表示", isOn: $style.showTeamsSection)
                } footer: {
                    Text("オフにすると、チーム名・スコア・タイマーなどは表示されず「試合情報」のみが表示されます。対戦相手が不明な場合や、複数チームと練習試合を行う場合などに利用できます。")
                }

                if style.showTeamsSection {
                    Section("オプション") {
                        Toggle("スコア表示", isOn: $style.showScore)
                        Toggle("タイマー表示", isOn: $style.showMatchTimer)
                        if style.showMatchTimer {
                            Picker("タイマー位置", selection: $style.timerPosition) {
                                ForEach(ScoreboardStyle.TimerPosition.allCases, id: \.self) { pos in
                                    Text(pos.displayName).tag(pos)
                                }
                            }
                            .pickerStyle(.segmented)

                            Toggle("タイマー詳細設定", isOn: $style.showTimerOptions)
                        }
                        Toggle("ペナルティタイマー", isOn: $style.showPenaltyTimer)
                        Toggle("タイムアウト", isOn: $style.showTimeouts)
                        Toggle("セットカウント表示", isOn: $style.showSetCount)
                    }
                }
            }
            .navigationTitle("スコアボード設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasUnsavedChanges {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        match.scoreboardStyle = style
                        let trimmedHome = homeTeamNameEdit.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedAway = awayTeamNameEdit.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedHome.isEmpty { match.homeTeamName = trimmedHome }
                        if !trimmedAway.isEmpty { match.awayTeamName = trimmedAway }
                        let trimmedInfo = matchInfoEdit.trimmingCharacters(in: .whitespacesAndNewlines)
                        match.matchInfo = trimmedInfo.isEmpty ? nil : trimmedInfo
                        TeamPresetStore.record(name: match.homeTeamName, colorHex: style.homeTeamColorHex)
                        dismiss()
                        onSave?()
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .sheet(isPresented: $showPresetPicker) {
            TeamPresetPickerSheet(presets: $teamPresets) { preset in
                homeTeamNameEdit = preset.name
                if let hex = preset.colorHex {
                    style.homeTeamColorHex = hex
                }
            }
        }
        .confirmationDialog(
            "変更を破棄しますか？",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("変更を破棄", role: .destructive) { dismiss() }
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("保存していない変更は失われます。")
        }
        .task {
            guard thumbnail == nil, let url = match.videoURLs.first else { return }
            thumbnail = await ThumbnailGenerator.generate(for: url)
            if let size = await ThumbnailGenerator.videoSize(for: url) {
                videoAspectRatio = size.width / size.height
            }
        }
    }

    // MARK: - Unsaved changes detection

    private var hasUnsavedChanges: Bool {
        if style != match.scoreboardStyle { return true }
        let trimmedHome = homeTeamNameEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAway = awayTeamNameEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHome.isEmpty && trimmedHome != match.homeTeamName { return true }
        if !trimmedAway.isEmpty && trimmedAway != match.awayTeamName { return true }
        let trimmedInfo = matchInfoEdit.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInfo != (match.matchInfo ?? "") { return true }
        return false
    }

    // MARK: - Color Bindings

    private var homeColorBinding: Binding<Color> {
        Binding(
            get: { style.homeTeamColor ?? Color.scoreboardText(for: style.theme) },
            set: { style.homeTeamColor = $0 }
        )
    }

    private var awayColorBinding: Binding<Color> {
        Binding(
            get: { style.awayTeamColor ?? Color.scoreboardText(for: style.theme) },
            set: { style.awayTeamColor = $0 }
        )
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if editTarget == .scoreboard {
                    style.scale = clamp(baseScale * value, min: 0.5, max: 2.5)
                } else {
                    style.matchInfoScale = clamp(baseMatchInfoScale * value, min: 0.5, max: 2.5)
                }
            }
            .onEnded { _ in
                if editTarget == .scoreboard {
                    baseScale = style.scale
                } else {
                    baseMatchInfoScale = style.matchInfoScale
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                if editTarget == .scoreboard {
                    style.positionX = clamp(basePosition.x + dx, min: 0, max: 0.95)
                    style.positionY = clamp(basePosition.y + dy, min: 0, max: 0.95)
                } else {
                    style.matchInfoPositionX = clamp(baseMatchInfoPosition.x + dx, min: 0, max: 0.95)
                    style.matchInfoPositionY = clamp(baseMatchInfoPosition.y + dy, min: 0, max: 0.95)
                }
            }
            .onEnded { _ in
                if editTarget == .scoreboard {
                    basePosition = CGPoint(x: style.positionX, y: style.positionY)
                } else {
                    baseMatchInfoPosition = CGPoint(x: style.matchInfoPositionX, y: style.matchInfoPositionY)
                }
            }
    }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}
