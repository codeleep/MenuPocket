import SwiftUI

/// Everyday access to icons. Group editing belongs exclusively to PocketView.
struct QuickPanel: View {
    @ObservedObject var state: AppState
    let groupID: String?
    let openSettings: () -> Void
    @State private var query = ""

    private var group: IconGroup? { state.layout.groups.first { $0.id == groupID } }
    private var title: String { group?.name ?? "全部图标" }
    private var matching: [MenuIcon] {
        let source = groupID == nil ? state.items : state.groupItems(groupID)
        return source.filter { query.isEmpty || state.displayName($0).localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: group?.symbol ?? "square.grid.2x2").foregroundStyle(.teal)
                Text(title).font(.headline)
                Text("\(matching.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if state.scanning || state.working { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 16).padding(.vertical, 13)
            if groupID == nil {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("查找图标", text: $query).textFieldStyle(.plain)
                }.padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider()
            if !state.trusted {
                VStack(spacing: 10) {
                    Image(systemName: "lock").font(.title2).foregroundStyle(.secondary)
                    Text("开启辅助功能后即可使用图标").font(.callout)
                    Button("前往权限设置", action: openSettings).buttonStyle(.bordered)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if matching.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                    Text(query.isEmpty ? "这个分组还没有图标" : "没有匹配的图标").font(.callout)
                    if query.isEmpty { Button("添加图标到分组", action: openSettings).buttonStyle(.borderless) }
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ScrollView {
                    if groupID == nil {
                        VStack(alignment: .leading, spacing: 13) {
                            ForEach(state.layout.groups) { group in
                                let items = matching.filter { state.layout.placements[$0.id]?.groupID == group.id }
                                if !items.isEmpty {
                                    HStack {
                                        Text(group.name).font(.caption.weight(.medium))
                                        if group.hidden { Image(systemName: "eye.slash").font(.caption2) }
                                    }.foregroundStyle(.secondary)
                                    grid(items)
                                }
                            }
                            let ungrouped = matching.filter { state.layout.placements[$0.id]?.groupID == nil }
                            if !ungrouped.isEmpty {
                                Text("未分组").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                grid(ungrouped)
                            }
                        }.padding(12)
                    } else { grid(matching).padding(12) }
                }.frame(height: groupID == nil ? 280 : min(280, CGFloat((matching.count + 3) / 4) * 78 + 24))
            }
            if !state.error.isEmpty {
                Text(state.error).font(.caption).foregroundStyle(.orange).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            Divider()
            HStack {
                Text("点击图标打开原菜单").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("管理与设置")
                    .accessibilityLabel("管理与设置")
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }.frame(width: 320)
    }

    private func grid(_ icons: [MenuIcon]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(icons) { item in
                Button { state.open(item) } label: {
                    VStack(spacing: 5) {
                        Image(nsImage: state.thumbnails[item.id] ?? item.image)
                            .resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(state.displayName(item)).font(.system(size: 10)).lineLimit(2)
                            .multilineTextAlignment(.center).frame(height: 26)
                    }.frame(maxWidth: .infinity).padding(.vertical, 7)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).help(state.displayName(item)).disabled(state.working)
                    .contextMenu {
                        Button("打开原图标") { state.open(item) }
                        Button("原图标右键操作") { state.open(item, rightClick: true) }
                        Divider()
                        Button("图标设置…") {
                            openSettings()
                            state.editingIcon = item
                        }
                    }
            }
        }
    }
}
