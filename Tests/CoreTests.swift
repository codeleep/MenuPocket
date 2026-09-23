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
        let network = layout.groups[1].id
        layout.move("wifi", into: network)
        layout.placements["wifi"]?.label = "无线网络"
        layout.move("vpn", into: network)
        check(layout.placements["wifi"]?.groupID == network, "归组应记录目标组")
        check(layout.placements["vpn"]!.order > layout.placements["wifi"]!.order, "拖入组应追加到末尾")
        let before = layout
        layout.move("vpn", into: "deleted-group")
        check(layout == before, "失效拖放目标不能破坏归组")
        layout.groups[1].hidden = true
        check(layout.placements == before.placements, "隐藏组入口不能修改组内图标")
        layout.move("vpn", into: layout.groups[0].id)
        check(layout.placements["vpn"]?.groupID == layout.groups[0].id, "应能在分组间移动")
        layout.move("vpn", into: nil)
        check(layout.placements["vpn"]?.groupID == nil, "应能移回未分组")
        layout.removeGroup(network)
        check(layout.placements["wifi"]?.groupID == nil, "删除组应保留图标并移入未分组")
        check(layout.placements["wifi"]?.label == "无线网络", "删除组应保留图标名称")

        var migration = Layout()
        migration.move("host-proxy", into: migration.groups[0].id)
        migration.placements["host-proxy"]?.label = "下载工具"
        let originalPlacement = migration.placements["host-proxy"]
        migration.migrateAliases(["host-proxy"], to: "source-app")
        check(migration.placements["source-app"] == originalPlacement, "识别宿主代理后应保留分组顺序和名称")
        check(migration.placements["host-proxy"] == nil, "应移除已确认的代理键")
        migration.move("new-proxy", into: migration.groups[1].id)
        migration.migrateAliases(["new-proxy", "source-app"], to: "source-app")
        check(migration.placements["source-app"] == originalPlacement, "已有真实图标设置不能被代理覆盖")
        check(migration.placements["new-proxy"] == nil, "已有真实设置也应清理旧代理")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MenuPocket-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LayoutRepository(url: directory.appendingPathComponent("layout.json"))
        let initial = try repository.load()
        check(initial.groups.count == 3 && initial.version == 2, "新配置应使用分组版结构")
        try repository.save(layout)
        let restored = try repository.load()
        check(restored == layout, "重启应保留中文名称、组入口状态和顺序")

        // Real v1 payload: hidden and pinned describe different things. Only group visibility survives.
        let legacy = Data("""
        {"version":1,"groups":[
          {"id":"work","name":"工作","symbol":"hammer","hidden":true},
          {"id":"system","name":"系统","symbol":"gear","hidden":false}
        ],"placements":{
          "hidden-app":{"groupID":"work","order":5,"label":"下载工具","pinned":false},
          "pinned-app":{"groupID":"system","order":2,"pinned":true},
          "ungrouped-app":{"order":3,"pinned":false}
        }}
        """.utf8)
        try legacy.write(to: repository.url)
        let upgraded = try repository.load()
        check(upgraded.version == 2, "v1 应迁移到分组版 v2")
        check(upgraded.groups.map(\.id) == ["work", "system"], "迁移应保留分组顺序")
        check(upgraded.groups[0].hidden && !upgraded.groups[1].hidden, "迁移应保留组入口状态")
        check(upgraded.placements["hidden-app"]?.groupID == "work", "原隐藏图标应保留归组")
        check(upgraded.placements["pinned-app"]?.groupID == "system", "原常驻图标应保留归组")
        check(upgraded.placements["hidden-app"]?.order == 5, "迁移应保留组内顺序")
        check(upgraded.placements["hidden-app"]?.label == "下载工具", "迁移应保留自定义名称")
        check(upgraded.placements["ungrouped-app"]?.groupID == nil, "未分组图标不应被重新归组")
        let backup = repository.url.appendingPathExtension("v1-backup")
        let backedUp = try Data(contentsOf: backup)
        check(backedUp == legacy, "迁移前应完整备份旧配置")
        let unchanged = try Data(contentsOf: repository.url)
        check(unchanged == legacy, "读取迁移结果不能先行覆盖旧文件")
        try repository.save(upgraded)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: repository.url)) as! [String: Any]
        let placements = json["placements"] as! [String: [String: Any]]
        check(placements.values.allSatisfy { $0["pinned"] == nil }, "新配置不应再保存单图标显示偏好")
        let reloaded = try repository.load()
        check(reloaded == upgraded, "迁移后的配置应完整往返")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(files.filter { $0.hasPrefix("layout.json.v1-backup") }.count == 1, "v2 重读不应再次迁移")
        // A later v1 import must not overwrite the first rollback backup.
        var anotherLegacy = try JSONSerialization.jsonObject(with: legacy) as! [String: Any]
        anotherLegacy["placements"] = [:]
        try JSONSerialization.data(withJSONObject: anotherLegacy).write(to: repository.url)
        _ = try repository.load()
        let firstBackup = try Data(contentsOf: backup)
        check(firstBackup == legacy, "后续导入不能覆盖首次备份")

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
        var duplicate = layout
        duplicate.groups.append(duplicate.groups[0])
        try repository.save(duplicate)
        do { _ = try repository.load(); fatalError("重复分组标识必须拒绝") }
        catch { passed += 1 }
        print("PASS: \(passed) grouping, migration and persistence assertions")
    }
}
