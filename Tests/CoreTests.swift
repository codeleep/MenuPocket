import Foundation

@main
struct CoreTests {
    static func main() throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            passed += 1
        }
        var layout = Layout()
        var migration = Layout()
        migration.move("host-proxy", into: migration.groups[0].id)
        migration.placements["host-proxy"]?.pinned = true
        let originalPlacement = migration.placements["host-proxy"]
        migration.migrateAliases(["host-proxy"], to: "source-app")
        check(migration.placements["source-app"] == originalPlacement, "识别宿主代理后应完整保留原分组顺序和偏好")
        check(migration.placements["host-proxy"] == nil, "已确认代理身份应清理旧键避免重复迁移")
        migration.move("new-proxy", into: migration.groups[1].id)
        migration.migrateAliases(["new-proxy", "source-app"], to: "source-app")
        check(migration.placements["source-app"] == originalPlacement, "已有真实图标设置不能被代理设置覆盖或删除")
        check(migration.placements["new-proxy"] == nil, "已有真实设置也应移除已确认的旧代理键")
        let initialVisibility = ["docker": false, "wifi": false, "battery": true]
        check(VisibilityDelta.changedIDs(previous: [:], current: initialVisibility) == Set(initialVisibility.keys), "首次发现应检查已有图标")
        var changedVisibility = initialVisibility
        changedVisibility["wifi"] = true
        check(VisibilityDelta.changedIDs(previous: initialVisibility, current: changedVisibility) == ["wifi"], "单项偏好变化只能应用该图标")
        check(VisibilityDelta.changedIDs(previous: changedVisibility, current: changedVisibility).isEmpty, "重复扫描不能重新应用图标")
        changedVisibility["new-app"] = true
        check(VisibilityDelta.changedIDs(previous: initialVisibility.merging(["wifi": true]) { _, new in new }, current: changedVisibility) == ["new-app"], "新应用出现只能应用新图标")
        check(VisibilityDelta.changedIDs(previous: changedVisibility, current: ["battery": true]).isEmpty, "应用退出不能触发其他图标重新应用")
        let network = layout.groups[1].id
        layout.move("com.apple.controlcenter|WiFi|0", into: network)
        check(!layout.keepInMenuBar("com.apple.controlcenter|WiFi|0"), "首次归组默认隐藏原图标")
        layout.placements["com.apple.controlcenter|WiFi|0"]?.pinned = true
        check(layout.keepInMenuBar("com.apple.controlcenter|WiFi|0"), "归组图标可以同时显示在菜单栏")
        layout.groups[1].hidden = true
        check(layout.keepInMenuBar("com.apple.controlcenter|WiFi|0"), "隐藏组入口不能覆盖单图标显示偏好")
        layout.groups[1].hidden = false
        check(layout.keepInMenuBar("com.apple.controlcenter|WiFi|0"), "恢复组入口保留单图标显示偏好")
        layout.placements["com.apple.controlcenter|WiFi|0"]?.pinned = false
        check(!layout.keepInMenuBar("com.apple.controlcenter|WiFi|0"), "关闭同时显示后应收起原图标")
        check(layout.placements["com.apple.controlcenter|WiFi|0"]?.groupID == network, "更改显示偏好不能移出分组")
        layout.placements["com.apple.controlcenter|WiFi|0"]?.pinned = true
        check(layout.keepInMenuBar("new-app"), "未分组的新图标必须保留在状态栏")
        layout.move("vpn", into: network)
        let beforeMove = ["vpn": layout.keepInMenuBar("vpn")]
        var regrouped = layout
        regrouped.move("vpn", into: layout.groups[0].id)
        check(VisibilityDelta.changedIDs(previous: beforeMove, current: ["vpn": regrouped.keepInMenuBar("vpn")]).isEmpty, "两组之间移动不应重新应用菜单栏偏好")
        check(layout.placements["vpn"]!.order > layout.placements["com.apple.controlcenter|WiFi|0"]!.order, "拖入组应追加到末尾")
        let before = layout
        layout.move("vpn", into: "deleted-group")
        check(layout == before, "失效拖放目标不能破坏归组")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MenuPocket-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LayoutRepository(url: directory.appendingPathComponent("layout.json"))
        let initial = try repository.load()
        check(initial.groups.count == 3, "首次运行有默认分组")
        try repository.save(layout)
        let restored = try repository.load()
        check(restored == layout, "重启应精确保留中文组名、隐藏状态、顺序和常驻偏好")
        layout.removeGroup(network)
        check(layout.placements["vpn"]?.groupID == nil, "删除组应保留图标并移入未分组")
        check(layout.keepInMenuBar("vpn"), "删除分组后应恢复原图标")
        let development = layout.groups[0].id
        layout.move("terminal", into: development)
        check(!layout.keepInMenuBar("terminal"), "加入分组应隐藏")
        layout.move("terminal", into: nil)
        check(layout.keepInMenuBar("terminal"), "移回未分组应恢复")
        check(layout.placements["com.apple.controlcenter|WiFi|0"]?.pinned == true, "删除组不能丢失图标偏好")
        try repository.save(layout)
        let bytes = try Data(contentsOf: repository.url)
        check(!bytes.isEmpty, "原子保存应有可读文件")
        let invalid = Data("{invalid configuration".utf8)
        try invalid.write(to: repository.url)
        do { _ = try repository.load(); fatalError("损坏文件不能被默认为新布局") }
        catch { passed += 1 }
        let retained = try Data(contentsOf: repository.url)
        check(retained == invalid, "读取失败不能覆盖用户文件")
        var future = layout
        future.version = 999
        try repository.save(future)
        do { _ = try repository.load(); fatalError("未知版本必须拒绝") }
        catch { passed += 1 }
        print("PASS: \(passed) layout and persistence assertions")
    }
}
