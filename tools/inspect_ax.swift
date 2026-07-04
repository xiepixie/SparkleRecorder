import Cocoa
import ApplicationServices

// 获取所有运行中的应用
let apps = NSWorkspace.shared.runningApplications

// 尝试寻找名字里包含姜饼人或 Cookie Run 的应用
let targetNameKeywords = ["Cookie Run", "CookieRun", "姜饼人", "Kingdom", "クッキーラン"]
let gameApp = apps.first(where: { app in
    guard let name = app.localizedName else { return false }
    return targetNameKeywords.contains(where: { name.localizedCaseInsensitiveContains($0) })
})

guard let game = gameApp else {
    print("❌ 未能检测到运行中的《姜饼人王国》应用。")
    print("请先启动游戏，然后再运行此探测脚本！")
    print("\n当前活跃的图形应用有:")
    for app in apps {
        if let name = app.localizedName, app.activationPolicy == .regular {
            print(" - \(name) (PID: \(app.processIdentifier))")
        }
    }
    exit(1)
}

print("==================================================")
print("✅ 成功定位到游戏应用!")
print("   应用名称: \(game.localizedName ?? "")")
print("   进程 PID: \(game.processIdentifier)")
print("==================================================")

let appRef = AXUIElementCreateApplication(game.processIdentifier)

// 递归打印 UI 控件树
func dumpElement(_ element: AXUIElement, depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    
    // 获取 Role (控件类型，如 AXButton, AXWindow)
    var roleVal: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
    let role = roleVal as? String ?? "UnknownRole"
    
    // 获取 Title (控件文案，如“重新挑战”)
    var titleVal: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal)
    let title = titleVal as? String ?? ""
    
    // 获取 Description (无障碍描述)
    var descVal: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descVal)
    let desc = descVal as? String ?? ""
    
    let info = [
        title.isEmpty ? nil : "Title: \"\(title)\"",
        desc.isEmpty ? nil : "Desc: \"\(desc)\""
    ].compactMap { $0 }.joined(separator: ", ")
    
    print("\(indent)- [\(role)] \(info)")
    
    // 递归子元素
    var childrenVal: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal)
    if result == .success, let children = childrenVal as? [AXUIElement] {
        for child in children {
            dumpElement(child, depth: depth + 1)
        }
    }
}

print("\n--- 开始扫描游戏内暴露给 macOS 的 UI 节点树 ---")
dumpElement(appRef)
print("--- 扫描结束 ---")
print("==================================================")
