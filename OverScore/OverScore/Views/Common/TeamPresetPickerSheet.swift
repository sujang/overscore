import SwiftUI

/// 過去に入力したチーム（名前・チームカラー）から選択するシート。スワイプで削除できる。
struct TeamPresetPickerSheet: View {
    @Binding var presets: [TeamPreset]
    let onSelect: (TeamPreset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if presets.isEmpty {
                    ContentUnavailableView("保存されたチームはありません", systemImage: "person.3")
                } else {
                    List {
                        Section {
                            ForEach(presets) { preset in
                                Button {
                                    onSelect(preset)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        TeamPresetColorDot(colorHex: preset.colorHex)
                                        Text(preset.name)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    TeamPresetStore.remove(name: presets[index].name)
                                }
                                presets.remove(atOffsets: offsets)
                            }
                        } footer: {
                            Text("スワイプで削除できます")
                        }
                    }
                }
            }
            .navigationTitle("過去のチーム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        // 呼び出し元フォームの編集モード（動画の並び替え用）を引き継がない
        .environment(\.editMode, .constant(.inactive))
        .presentationDetents([.medium, .large])
    }
}

/// プリセットのチームカラーを示す丸。未設定のときは枠線のみ。
struct TeamPresetColorDot: View {
    let colorHex: String?

    var body: some View {
        Circle()
            .fill(colorHex.flatMap { Color(hex: $0) } ?? Color.clear)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
    }
}
