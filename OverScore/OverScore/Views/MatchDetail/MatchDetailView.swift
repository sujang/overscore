import SwiftUI

struct MatchDetailView: View {
    @Environment(Router.self) private var router
    @Bindable var match: Match
    @State private var showStyleSheet = false
    @State private var showVideoSheet = false
    @State private var thumbnail: UIImage?
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if match.skipOverlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(videoAspectRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        ScoreboardPreviewView(
                            homeTeamName: match.homeTeamName,
                            awayTeamName: match.awayTeamName,
                            homeScore: match.homeScore,
                            awayScore: match.awayScore,
                            style: match.scoreboardStyle,
                            currentPeriodLabel: match.timerSegments.first?.periodLabel,
                            matchInfo: match.matchInfo,
                            pkKicks: match.pkKicks,
                            thumbnail: thumbnail,
                            videoAspectRatio: videoAspectRatio,
                            homeSetCount: match.homeSetCount,
                            awaySetCount: match.awaySetCount
                        )
                    }

                    HStack {
                        VStack {
                            Text(match.homeTeamName)
                                .font(.headline)
                            Text("\(match.homeScore)")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)

                        Text("-")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        VStack {
                            Text(match.awayTeamName)
                                .font(.headline)
                            Text("\(match.awayScore)")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text(match.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("イベント") {
                if timelineItems.isEmpty {
                    Text("イベント記録がありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(timelineItems) { item in
                        switch item.kind {
                        case .goal(let team, let homeScore, let awayScore, let periodLabel):
                            HStack {
                                Text(TimeFormatting.format(seconds: item.timestamp))
                                    .monospacedDigit()
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Image(systemName: match.sportType.goalSystemImage)
                                    .foregroundStyle(team == .home ? .blue : .red)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(team == .home ? match.homeTeamName : match.awayTeamName)
                                        .font(.subheadline)
                                    if let periodLabel {
                                        Text(periodLabel)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text("\(homeScore) - \(awayScore)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        case .segmentStart(let label):
                            HStack {
                                Text(TimeFormatting.format(seconds: item.timestamp))
                                    .monospacedDigit()
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.purple)

                                Text(label)
                                    .font(.subheadline.weight(.medium))

                                Spacer()
                            }
                        case .kickoff(let label):
                            HStack {
                                Text(TimeFormatting.format(seconds: item.timestamp))
                                    .monospacedDigit()
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Image(systemName: "play.fill")
                                    .foregroundStyle(.green)

                                Text(label)
                                    .font(.subheadline.weight(.medium))

                                Spacer()
                            }
                        case .periodEnd(let label):
                            HStack {
                                Text(TimeFormatting.format(seconds: item.timestamp))
                                    .monospacedDigit()
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Image(systemName: "stop.fill")
                                    .foregroundStyle(.orange)

                                Text(label)
                                    .font(.subheadline.weight(.medium))

                                Spacer()
                            }
                        }
                    }
                }
            }

            if !match.pkKicks.isEmpty {
                Section("PK戦 (\(match.homePKScore) - \(match.awayPKScore))") {
                    VStack(alignment: .leading, spacing: 4) {
                        if match.pkKicks.firstKickingTeam == .home {
                            pkResultRow(teamName: match.homeTeamName, kicks: match.homePKKicks)
                            pkResultRow(teamName: match.awayTeamName, kicks: match.awayPKKicks)
                        } else {
                            pkResultRow(teamName: match.awayTeamName, kicks: match.awayPKKicks)
                            pkResultRow(teamName: match.homeTeamName, kicks: match.homePKKicks)
                        }
                    }
                }
            }

            Section("エクスポート設定") {
                Toggle(isOn: $match.skipOverlay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("動画のみ結合")
                        Text("スコアボードを付けず元の動画をそのまま結合します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    showVideoSheet = true
                } label: {
                    Label("動画管理", systemImage: "film.stack")
                }

                Button {
                    router.navigate(to: .scoreEditor(match))
                } label: {
                    Label("スコア編集", systemImage: "pencil")
                }
                .disabled(match.skipOverlay)

                Button {
                    showStyleSheet = true
                } label: {
                    Label("スコアボード設定", systemImage: "paintbrush")
                }
                .disabled(match.skipOverlay)
            } header: {
                Text("アクション")
            } footer: {
                if match.skipOverlay {
                    Label(
                        "「動画のみ結合」がオンのため、スコア編集とスコアボード設定は使用できません。上の設定をオフにすると編集できます。",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Button {
                router.navigate(to: .export(match))
            } label: {
                Label("エクスポート", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(match.videoURLs.isEmpty)
            .padding()
            .background(.bar)
        }
        .navigationTitle("試合詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    router.popToRoot()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("一覧")
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showVideoSheet) {
            VideoManagementSheet(match: match)
        }
        .sheet(isPresented: $showStyleSheet) {
            ScoreboardStyleSheet(match: match, thumbnail: thumbnail, videoAspectRatio: videoAspectRatio)
        }
        .task(id: match.videoBookmarksData ?? match.videoBookmark) {
            guard let url = match.videoURLs.first else {
                thumbnail = nil
                return
            }
            thumbnail = await ThumbnailGenerator.generate(for: url)
            if let size = await ThumbnailGenerator.videoSize(for: url) {
                videoAspectRatio = size.width / size.height
            }
        }
    }

    private func pkResultRow(teamName: String, kicks: [PKKick]) -> some View {
        HStack(spacing: 6) {
            Text(teamName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            ForEach(kicks) { kick in
                Text(kick.isGoal ? "◯" : "✗")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(kick.isGoal ? .green : .red)
                    .frame(width: 22)
            }
            Spacer()
        }
    }

    private func periodLabel(at timestamp: TimeInterval, segments: [TimerSegment]) -> String? {
        for (i, seg) in segments.enumerated().reversed() {
            let start = seg.effectiveStartTime ?? 0
            if timestamp >= start {
                return seg.periodLabel ?? (segments.count > 1 ? String(localized: "セグメント \(i + 1)") : nil)
            }
        }
        return segments.first?.periodLabel
    }

    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []

        // セグメントイベント
        for (i, seg) in match.timerSegments.enumerated() {
            let label = seg.periodLabel ?? String(localized: "セグメント \(i + 1)")

            if let start = seg.segmentStartTime {
                items.append(TimelineItem(
                    timestamp: start,
                    kind: .segmentStart(label: label)
                ))
            }

            if let kickoff = seg.timerStartTime {
                items.append(TimelineItem(
                    timestamp: kickoff,
                    kind: .kickoff(label: String(localized: "\(label) キックオフ"))
                ))
            }

            if let stop = seg.timerStopTime {
                items.append(TimelineItem(
                    timestamp: stop,
                    kind: .periodEnd(label: String(localized: "\(label) 終了"))
                ))
            }
        }

        // スコアイベント
        let segments = match.timerSegments
        let sorted = match.sortedEvents
        var home = 0
        var away = 0
        for event in sorted {
            switch event.team {
            case .home: home += 1
            case .away: away += 1
            }
            let period = periodLabel(at: event.timestamp, segments: segments)
            items.append(TimelineItem(
                timestamp: event.timestamp,
                kind: .goal(team: event.team, homeScore: home, awayScore: away, periodLabel: period)
            ))
        }

        return items.sorted { $0.timestamp < $1.timestamp }
    }
}

private struct TimelineItem: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let kind: Kind

    enum Kind {
        case goal(team: Team, homeScore: Int, awayScore: Int, periodLabel: String?)
        case segmentStart(label: String)
        case kickoff(label: String)
        case periodEnd(label: String)
    }
}
