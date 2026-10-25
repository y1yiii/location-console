import SwiftUI
import AppKit

@main struct LocationConsoleApp: App {
    @NSApplicationDelegateAdaptor(ConsoleDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        Window("定位控制台", id: "main") {
            ConsoleView().environmentObject(model).frame(minWidth: 940, minHeight: 680)
        }
        .defaultSize(width: 1120, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入 GPX…") { model.importGPX() }.keyboardShortcut("o").disabled(model.busy || model.simulation != nil)
            }
            CommandMenu("定位控制") {
                Button("控制台") { model.page = .home }.keyboardShortcut("1")
                Button("固定定位") { model.page = .coordinate }.keyboardShortcut("2")
                Button("路线回放") { model.page = .route }.keyboardShortcut("3")
                Button("环境检查") { model.page = .setup }.keyboardShortcut("4")
                Divider()
                Button("刷新设备") { Task { await model.refresh() } }.keyboardShortcut("r").disabled(!model.canRefresh)
                Button("停止并清除模拟") { Task { await model.clear() } }.keyboardShortcut(".")
                    .disabled(model.busy || (model.simulation == nil && model.selectedPhone == nil))
            }
            CommandGroup(replacing: .help) {
                Button("定位控制台帮助") { model.page = .help }
                Button("完整使用说明") { model.openDocumentation() }
            }
        }
    }
}

@MainActor final class ConsoleDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(self, selector: #selector(configureWindow(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        DispatchQueue.main.async {
            for window in NSApp.windows where !(window is NSPanel) { window.delegate = self }
        }
    }
    @objc private func configureWindow(_ notification: Notification) {
        if let window = notification.object as? NSWindow, !(window is NSPanel) { window.delegate = self }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        if (model.isRefreshing || model.isCheckingEnvironment), model.simulation == nil {
            model.cancelRead()
            model.allowSleep()
            return .terminateNow
        }
        if model.busy {
            let alert = NSAlert()
            alert.messageText = "请等待当前操作完成"
            alert.informativeText = "Xcode 命令仍在执行，完成后再退出。"
            alert.runModal()
            return .terminateCancel
        }
        guard model.simulation != nil else { model.allowSleep(); return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "模拟会话还没有清除"
        alert.informativeText = "关闭软件或拔线不保证恢复真实位置。可以先清除再退出；清除后仍需在手机地图确认。"
        alert.addButton(withTitle: "清除并退出")
        alert.addButton(withTitle: "返回软件")
        alert.addButton(withTitle: "保留模拟并退出")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                let success = await model.clear()
                if success { model.allowSleep() }
                sender.reply(toApplicationShouldTerminate: success)
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            model.addLog("用户选择保留模拟并退出；设备状态将在下次启动时提示核对。")
            model.allowSleep()
            return .terminateNow
        default: return .terminateCancel
        }
    }
}
