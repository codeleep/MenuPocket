import SwiftUI
import UniformTypeIdentifiers
import ApplicationServices

struct PocketView: View {
    @ObservedObject var state: AppState
    @State private var newName = ""
    @State private var adding = false
    @State private var renaming: IconGroup?
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if !state.trusted { permissionBanner }
                if !state.error.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(state.error).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { state.error = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(12).background(.orange.opacity(0.08))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if state.items.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "menubar.rectangle").font(.system(size: 40)).foregroundStyle(.secondary)
                                Text(state.scanning ? "正在读取菜单栏…" : "暂未发现菜单栏图标").font(.title3.weight(.semibold))
                                Text(state.trusted ? "点击刷新重新扫描。已退出应用的图标不会出现在这里。" : "授权辅助功能后，可读取更多图标名称并操作原菜单。").foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 70)
                        } else if let selected = state.selectedGroup {
                            if selected == "ungrouped" { section(nil) }
                            else if let group = state.layout.groups.first(where: { $0.id == selected }) { section(group) }
                        } else {
                            ForEach(state.layout.groups) { section($0) }
                            section(nil)
                        }
                    }.padding(22)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("新建分组", isPresented: $adding) {
            TextField("分组名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") { state.createGroup(newName); newName = "" }
        } message: { Text("分组名称也会显示在菜单栏，建议保持简短。") }
        .alert("重命名分组", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") { if let group = renaming { state.rename(group, to: renameText) }; renaming = nil }
        }
        .sheet(isPresented: $state.showingPermissions) { PermissionsView(state: state) }
        .sheet(item: $state.editingIcon) { item in IconSettingsView(state: state, item: item) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(.teal)
                Text("MenuPocket").font(.headline)
            }.padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 18)
            sideRow("全部图标", symbol: "square.grid.2x2", id: nil, count: state.items.count)
            Text("分组").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 16)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(state.layout.groups) { group in
                        sideRow(group.name, symbol: group.hidden ? "eye.slash" : group.symbol, id: group.id, count: state.groupItems(group.id).count)
                            .contextMenu { groupMenu(group) }
                            .onDrop(of: [.utf8PlainText], isTargeted: nil) { drop($0, into: group.id) }
                    }
                    sideRow("未分组", symbol: "tray", id: "ungrouped", count: state.groupItems(nil).count)
                        .onDrop(of: [.utf8PlainText], isTargeted: nil) { drop($0, into: nil) }
                }
            }
            Button { adding = true } label: { Label("新建分组", systemImage: "plus") }
                .buttonStyle(.plain).padding(14)
            Divider()
            Button { state.showingPermissions = true } label: { Label("权限与说明", systemImage: "hand.raised") }
                .buttonStyle(.plain).padding(14)
            Text("拖动图标到分组即可归类").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 18)
        }.frame(width: 190).background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func sideRow(_ title: String, symbol: String, id: String?, count: Int) -> some View {
        Button { state.selectedGroup = id } label: {
            HStack {
                Image(systemName: symbol).frame(width: 18)
                Text(title).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .background(state.selectedGroup == id ? Color.teal.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.selectedGroup == nil ? "全部图标" : state.layout.groups.first(where: { $0.id == state.selectedGroup })?.name ?? "未分组")
                        .font(.system(size: 25, weight: .semibold))
                    Text("你的菜单栏，按自己的方式整理。") .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if state.scanning || state.working { ProgressView().controlSize(.small) }
                Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新图标").disabled(state.scanning || state.working)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索图标或应用名称", text: $state.search).textFieldStyle(.plain)
                if !state.search.isEmpty { Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }.padding(22)
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "lock.open").foregroundStyle(.teal)
            Text("辅助功能未授权：授权后读取真实图标，并启用原菜单操作。").font(.caption)
            Spacer()
            Button("去授权") { state.showingPermissions = true }
        }.padding(12).background(.teal.opacity(0.08))
    }

    private func section(_ group: IconGroup?) -> some View {
        let icons = state.filtered(group?.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: group?.symbol ?? "tray").foregroundStyle(.teal)
                Text(group?.name ?? "未分组").font(.headline)
                Text("\(icons.count)").foregroundStyle(.secondary).font(.caption)
                if group?.hidden == true { Text("已隐藏入口").font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).background(.quaternary, in: Capsule()) }
                Spacer()
                if let group {
                    Button(group.hidden ? "恢复显示" : "隐藏组") { state.hide(group) }.buttonStyle(.borderless).disabled(state.working)
                    Menu { groupMenu(group) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                }
            }
            if icons.isEmpty {
                Text(state.search.isEmpty ? "把图标拖到这里，或从图标菜单中选择分组。" : "此组没有匹配的图标。")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 160), spacing: 12)], spacing: 12) {
                    ForEach(icons) { item in
                        IconTile(state: state, item: item) { state.editingIcon = item }
                    }
                }
            }
        }.onDrop(of: [.utf8PlainText], isTargeted: nil) { drop($0, into: group?.id) }
    }

    @ViewBuilder private func groupMenu(_ group: IconGroup) -> some View {
        Button("重命名") { renaming = group; renameText = group.name }
        Button(group.hidden ? "恢复菜单栏入口" : "隐藏此组") { state.hide(group) }
        Button("上移") { state.reorderGroup(group, by: -1) }
        Button("下移") { state.reorderGroup(group, by: 1) }
        Divider()
        Button("删除分组，图标移到未分组") { state.delete(group) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("点击图标设置显示偏好和分组；使用图标请点击菜单栏的分组入口。")
                .font(.caption).foregroundStyle(.secondary)
            Text(state.message)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
        }.padding(14)
    }

    private func drop(_ providers: [NSItemProvider], into groupID: String?) -> Bool {
        guard !state.working, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in state.move(id, groupID: groupID) }
        }
        return true
    }
}

struct IconTile: View {
    @ObservedObject var state: AppState
    let item: MenuIcon
    let edit: () -> Void

    var body: some View {
        Button(action: edit) { 
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: state.thumbnails[item.id] ?? item.image).resizable().scaledToFit().frame(width: 30, height: 30)
                        .frame(maxWidth: .infinity)
                }
                Text(state.displayName(item)).font(.callout).lineLimit(2).multilineTextAlignment(.center).frame(height: 34)
                Text(item.isSystem ? "系统图标" : item.appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if state.layout.placements[item.id]?.groupID != nil {
                    Label(state.visibility[item.id]?.badgeText ?? "等待应用显示偏好",
                          systemImage: state.layout.keepInMenuBar(item.id) ? "pin.fill" : "folder")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(12).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07)))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(state.working)
            .help("设置 \(state.displayName(item)) 的显示偏好和分组")
            .onDrag { NSItemProvider(object: item.id as NSString) }
            .contextMenu {
                Button("图标设置…", action: edit)
                Divider()
                Menu("移到分组") {
                    Button("未分组") { state.move(item.id, groupID: nil) }
                    ForEach(state.layout.groups) { group in Button(group.name) { state.move(item.id, groupID: group.id) } }
                }
                Button("在组内前移") { state.reorder(item, by: -1) }
                Button("在组内后移") { state.reorder(item, by: 1) }
            }
    }
}

struct IconSettingsView: View {
    @ObservedObject var state: AppState
    let item: MenuIcon
    @Environment(\.dismiss) private var dismiss

    private var groupID: String? { state.layout.placements[item.id]?.groupID }
    private var isAvailable: Bool { state.items.contains { $0.id == item.id } }
    private var ordered: [MenuIcon] { state.groupItems(groupID) }
    private var position: Int? { ordered.firstIndex { $0.id == item.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: state.thumbnails[item.id] ?? item.image)
                    .resizable().scaledToFit().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("图标设置").font(.title2.weight(.semibold))
                    Text(state.displayName(item)).font(.headline).lineLimit(2)
                    Text(item.appName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("所在分组").font(.headline)
                Picker("移动到", selection: Binding(
                    get: { groupID ?? "" },
                    set: { state.move(item.id, groupID: $0.isEmpty ? nil : $0) }
                )) {
                    Text("未分组").tag("")
                    ForEach(state.layout.groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                HStack {
                    Text(position.map { "组内第 \($0 + 1) 个，共 \(ordered.count) 个" } ?? "图标暂不可用")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("前移") { state.reorder(item, by: -1) }
                        .disabled(position == nil || position == 0)
                    Button("后移") { state.reorder(item, by: 1) }
                        .disabled(position == nil || position == ordered.count - 1)
                }
            }.disabled(state.working || !isAvailable)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("显示偏好").font(.headline)
                Picker("显示位置", selection: Binding(
                    get: { state.layout.keepInMenuBar(item.id) },
                    set: { state.setMenuBarVisible(item.id, visible: $0) }
                )) {
                    Text("菜单栏和分组都显示").tag(true)
                    Text("仅在分组显示").tag(false)
                }.pickerStyle(.radioGroup).labelsHidden()
                    .disabled(groupID == nil || state.working || !isAvailable)
                if groupID == nil {
                    Text("先选择一个分组，再设置显示偏好。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label(state.visibility[item.id]?.text ?? "等待应用显示偏好", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if case .failed = state.visibility[item.id] {
                        Button("重试应用显示偏好") { state.retryVisibility?(item.id) }
                            .disabled(state.working || !isAvailable)
                    }
                }
            }
            if !isAvailable {
                Text("原图标已退出或发生变化，分组设置已保留；请关闭后刷新列表。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !state.error.isEmpty {
                Text(state.error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text("修改后自动保存").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 430)
    }
}

struct PermissionsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("让图标真正可操作").font(.title2.weight(.semibold))
            Text("MenuPocket 需要辅助功能权限读取菜单栏项目、调用原菜单。权限必须由你在系统设置中开启。")
            HStack {
                Label(state.trusted ? "辅助功能已开启" : "辅助功能未开启", systemImage: state.trusted ? "checkmark.circle.fill" : "lock")
                Spacer()
                Button("打开系统设置") { state.requestAccessibility() }
            }
            Divider()
            Text("原图标预览（可选）").font(.headline)
            Text("屏幕录制权限用于读取菜单栏图标图片。不授权时使用应用图标或系统符号；不会录制视频、保存屏幕内容或上传数据。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("开启图标预览") { ThumbnailService.requestPermission() }
                Button("刷新图标预览") { Task { await ThumbnailService.refresh(state: state) } }
            }
            Divider()
            Text("使用方式").font(.headline)
            Text("• 点击菜单栏分组使用图标；点击管理界面图标修改设置。\n• 隐藏组只隐藏组入口，仍能从“全部图标”访问。\n• ⌃⌥⌘B 打开全部图标。\n• 选择“仅在分组显示”会自动隐藏支持移动的原图标。无法操作的项目会显示“未生效”，可点击查看原因。")
                .font(.callout)
            HStack {
                Button("退出 MenuPocket") { NSApp.terminate(nil) }
                Spacer()
                Button("已设置，重新检查") { state.refresh(); state.showingPermissions = false }
                    .buttonStyle(.borderedProminent).tint(.teal)
            }
        }.padding(28).frame(width: 530)
    }
}
