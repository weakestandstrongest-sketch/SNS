import SwiftUI

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    /// 画面セット（保存用の文字列）。"youtube,x;instagram,threads" のような形
    @AppStorage("sets") private var setsText = ScreenSet.encode(ScreenSet.defaults)
    /// 表示中の画面セットの番号
    @AppStorage("selected") private var selected = 0
    /// 上の画面が占める割合（0.2〜0.8）
    @AppStorage("ratio") private var ratio = 0.5
    /// 1 画面だけ大きく表示しているときの位置（0 = 上 / 1 = 下）
    @State private var maximizedSlot: Int?
    /// 組み合わせの追加・変更画面
    @State private var editing: SetEdit?

    private struct SetEdit: Identifiable {
        let id = UUID()
        /// nil なら新しく追加
        let index: Int?
        let set: ScreenSet
    }

    private var sets: [ScreenSet] { ScreenSet.decode(setsText) }
    private var current: ScreenSet { sets[min(max(selected, 0), sets.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                panes(in: geo.size, landscape: landscape)
            }
            SetSwitcher(
                sets: sets,
                selected: $selected,
                onSelect: { maximizedSlot = nil },
                onAdd: { editing = SetEdit(index: nil, set: ScreenSet(top: .youtube, bottom: .instagram)) },
                onEdit: { index in editing = SetEdit(index: index, set: sets[index]) },
                onDelete: deleteSet
            )
        }
        .background(Color(.systemBackground))
        .sheet(item: $editing) { edit in
            SetEditor(set: edit.set, isNew: edit.index == nil) { newSet in
                var all = sets
                if let index = edit.index {
                    all[index] = newSet
                    selected = index
                } else {
                    all.append(newSet)
                    selected = all.count - 1
                }
                maximizedSlot = nil
                setsText = ScreenSet.encode(all)
            }
        }
    }

    private func deleteSet(_ index: Int) {
        var all = sets
        guard all.count > 1 else { return }
        all.remove(at: index)
        if selected > index || selected >= all.count { selected = max(0, selected - 1) }
        maximizedSlot = nil
        setsText = ScreenSet.encode(all)
    }

    @ViewBuilder
    private func panes(in size: CGSize, landscape: Bool) -> some View {
        if let slot = maximizedSlot {
            pane(slot: slot)
        } else {
            let handle: CGFloat = 12
            let total = (landscape ? size.width : size.height) - handle
            let first = total * ratio
            let layout = landscape ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                pane(slot: 0)
                    .frame(width: landscape ? first : nil, height: landscape ? nil : first)
                DividerHandle(landscape: landscape)
                    .frame(width: landscape ? handle : nil, height: landscape ? nil : handle)
                    .gesture(
                        DragGesture(coordinateSpace: .named("panes")).onChanged { value in
                            let position = landscape ? value.location.x : value.location.y
                            ratio = min(0.8, max(0.2, (position - handle / 2) / total))
                        }
                    )
                pane(slot: 1)
            }
            .coordinateSpace(name: "panes")
        }
    }

    private func pane(slot: Int) -> some View {
        let sns = current[slot]
        return PaneView(
            browser: store.browser(for: sns),
            other: current[1 - slot],
            isMaximized: maximizedSlot == slot,
            onChange: { newSNS in
                var all = sets
                all[min(max(selected, 0), all.count - 1)][slot] = newSNS
                setsText = ScreenSet.encode(all)
            },
            onToggleMaximize: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    maximizedSlot = maximizedSlot == nil ? slot : nil
                }
            }
        )
        .id(sns)
    }
}

/// 上下の画面の境目。ドラッグで大きさを変えられる。
private struct DividerHandle: View {
    let landscape: Bool

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: landscape ? 4 : 36, height: landscape ? 36 : 4)
        }
        .contentShape(Rectangle())
    }
}

/// SNS 1 つ分の画面（見出し＋ページ）
private struct PaneView: View {
    @ObservedObject var browser: Browser
    /// もう片方の画面に出ている SNS（同じ SNS は選べない）
    let other: SNS
    let isMaximized: Bool
    let onChange: (SNS) -> Void
    let onToggleMaximize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                WebViewContainer(webView: browser.webView)
                if browser.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(browser.sns.color)
                        .scaleEffect(x: 1, y: 0.5)
                }
            }
        }
        .onAppear { browser.loadIfNeeded() }
        .sheet(item: $browser.popup) { popup in
            NavigationStack {
                WebViewContainer(webView: popup.webView)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("ログイン")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        Button("閉じる") { browser.popup = nil }
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(SNS.allCases) { sns in
                    Button {
                        onChange(sns)
                    } label: {
                        if sns == browser.sns { Label(sns.name, systemImage: "checkmark") } else { Text(sns.name) }
                    }
                    .disabled(sns == other)
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(browser.sns.color).frame(width: 8, height: 8)
                    Text(browser.sns.name).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            HeaderButton(systemImage: "chevron.backward", label: "戻る", action: browser.goBack)
                .disabled(!browser.canGoBack)
            HeaderButton(systemImage: "arrow.clockwise", label: "再読み込み", action: browser.reload)
            HeaderButton(systemImage: "house", label: "ホーム", action: browser.goHome)
            HeaderButton(
                systemImage: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: isMaximized ? "2 画面に戻す" : "この画面だけ表示",
                action: onToggleMaximize
            )
        }
        .frame(height: 36)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) {
            browser.sns.color.frame(height: 2)
        }
    }
}

private struct HeaderButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .tint(.secondary)
    }
}

/// 画面下の、画面セットを切り替えるボタン。長押しで組み合わせの変更・削除。
private struct SetSwitcher: View {
    let sets: [ScreenSet]
    @Binding var selected: Int
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sets.indices, id: \.self) { index in
                        setButton(index: index)
                    }
                }
                .padding(.horizontal, 8)
                // 2 つ以下のときは横幅いっぱいに並べる
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                    sets.count <= 2 ? width : max(width, CGFloat(sets.count) * 150)
                }
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 40, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
            }
            .accessibilityLabel("組み合わせを追加")
            .tint(.primary)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func setButton(index: Int) -> some View {
        let set = sets[index]
        let isSelected = index == selected
        return Button {
            selected = index
            onSelect()
        } label: {
            HStack(spacing: 5) {
                Circle().fill(set.top.color).frame(width: 8, height: 8)
                Text(set.top.name)
                Text("＋").foregroundStyle(.secondary)
                Circle().fill(set.bottom.color).frame(width: 8, height: 8)
                Text(set.bottom.name)
            }
            .font(.footnote.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(.tertiarySystemFill) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onEdit(index) } label: { Label("組み合わせを変更", systemImage: "pencil") }
            if sets.count > 1 {
                Button(role: .destructive) { onDelete(index) } label: { Label("削除", systemImage: "trash") }
            }
        }
    }
}

/// 組み合わせを選ぶ画面
private struct SetEditor: View {
    @State var set: ScreenSet
    let isNew: Bool
    let onSave: (ScreenSet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                picker("上の画面", slot: 0)
                picker("下の画面", slot: 1)
            }
            .navigationTitle(isNew ? "組み合わせを追加" : "組み合わせを変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") {
                        onSave(set)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func picker(_ title: String, slot: Int) -> some View {
        Section(title) {
            Picker(title, selection: $set[slot]) {
                ForEach(SNS.allCases) { sns in
                    HStack {
                        Circle().fill(sns.color).frame(width: 10, height: 10)
                        Text(sns.name)
                    }
                    .tag(sns)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .onChange(of: set[slot]) { _, newValue in
                // 上下で同じ SNS になったら、もう片方を入れ替える
                if set[1 - slot] == newValue {
                    set[1 - slot] = SNS.allCases.first { $0 != newValue }!
                }
            }
        }
    }
}
