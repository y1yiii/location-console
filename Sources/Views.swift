import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let accent = Color(red: 0.12, green: 0.48, blue: 0.95)
private let teal = Color(red: 0.04, green: 0.62, blue: 0.56)

struct ConsoleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "location.north.circle.fill").font(.system(size: 32)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("定位控制台").font(.headline)
                        Text("iPhone · Mac").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20).padding(.top, 8)
                List(selection: $model.page) {
                    ForEach(Page.allCases) { page in
                        Label(page.rawValue, systemImage: page.icon).tag(page).padding(.vertical, 5)
                    }
                }.listStyle(.sidebar)
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.simulation == nil ? "等待操作" : "模拟会话未清除", systemImage: model.simulation == nil ? "circle.dotted" : "location.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(model.simulation == nil ? Color.secondary : teal)
                    Text("路线在本机处理").font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 250)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        ScrollView { Text(error).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 110)
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(16).background(Color.orange.opacity(0.10))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch model.page ?? .home {
                        case .home: HomePage()
                        case .setup: SetupPage()
                        case .coordinate: CoordinatePage()
                        case .route: RoutePage()
                        case .logs: LogsPage()
                        case .help: HelpPage()
                        }
                    }.padding(30).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
                }
                Divider()
                HStack(spacing: 10) {
                    if model.busy {
                        ProgressView().controlSize(.small); Text(model.operation)
                        if model.isRefreshing || model.isCheckingEnvironment { Button("取消读取") { model.cancelRead() }.controlSize(.small) }
                    }
                    else { Image(systemName: "info.circle"); Text(model.notice).lineLimit(2) }
                    Spacer(minLength: 0)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 12)
                    .frame(minHeight: 48)
            }.background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle((model.page ?? .home).rawValue)
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await model.refresh() } } label: { Label("刷新设备", systemImage: "arrow.clockwise") }.disabled(!model.canRefresh)
                    Button { Task { await model.clear() } } label: { Label("停止并清除", systemImage: "stop.circle") }
                        .disabled(model.busy || (model.simulation == nil && model.selectedPhone == nil))
                        .help("清除模拟定位；恢复情况请在手机地图确认")
                }
            }
        }.tint(accent)
        .task { await model.prepare() }
    }
}

private struct PageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.caption.weight(.semibold)).tracking(1.8).foregroundStyle(teal)
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(.headline) }
            content
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06)))
    }
}

private struct HomePage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageTitle(eyebrow: "LOCATION CONSOLE", title: "从这里开始", subtitle: "连接手机、设置一个坐标，或沿你画好的 GPX 路线移动。")
        EnvironmentSummaryCard()
        DeviceCard()
        if model.simulation != nil { SessionCard() }
        HStack(alignment: .top, spacing: 16) {
            ActionCard(icon: "mappin.and.ellipse", title: "固定定位", detail: "输入经纬度，将位置停留在指定地点。", color: accent) { model.page = .coordinate }
            ActionCard(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "路线回放", detail: "导入 GPX，设置总耗时，单次播放到终点。", color: teal) { model.page = .route }
        }
        Card(title: "使用顺序") {
            HStack(alignment: .top, spacing: 20) {
                StepView(number: "01", title: "连接设备", detail: "用数据线连接，解锁并信任 Mac。")
                StepView(number: "02", title: "设置位置", detail: "选择坐标或导入一条连续 GPX。")
                StepView(number: "03", title: "完成后清除", detail: "结束记录，再停止并核对真实位置。")
            }
        }
    }
}

private struct EnvironmentSummaryCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: model.environmentReport?.supportsRoutes == true && model.phoneReady ? "checkmark.circle.fill" : "checklist")
                    .font(.title2).foregroundStyle(teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.environmentReport?.supportsRoutes == true && model.phoneReady ? "环境和设备已就绪" : "首次使用，先检查环境与设备").font(.headline)
                    Text("自动检查 Xcode 初始化及定位接口，按提示准备手机。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("查看环境检查") { model.page = .setup }
            }
        }
    }
}

private struct SetupPage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageTitle(eyebrow: "GET READY", title: "环境检查", subtitle: "完成本机环境检查，再连接并准备 iPhone。检查会读取工具帮助和设备列表，不会开始定位模拟。")
        Card {
            HStack {
                Text("1 · 本机与 Xcode").font(.headline)
                Spacer()
                Button(model.isCheckingEnvironment ? "检查中…" : "检查环境与设备") { Task { await model.prepare() } }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
            }
            HStack {
                TextField("Xcode.app 路径", text: $model.xcodePath).textFieldStyle(.roundedBorder).disabled(model.busy || model.simulation != nil)
                Button("选择 Xcode…") { model.selectXcode() }.disabled(model.busy || model.simulation != nil)
            }
            HStack(spacing: 16) {
                Button("打开 Xcode") { model.openXcode() }
                    .disabled((try? DeviceService.developerDirectory(model.xcodePath)) == nil)
                Link("获取 Xcode", destination: URL(string: "https://developer.apple.com/xcode/")!)
                Button("导出环境报告") { model.exportEnvironmentReport() }.disabled(model.busy)
            }.font(.callout)
            Divider()
            if let report = model.environmentReport {
                ForEach(report.checks) { check in SetupCheckRow(check: check) }
                Text("检查时间：\(report.checkedAt.formatted(date: .abbreviated, time: .shortened))。接口可用表示工具已提供此命令，实际设备兼容性仍以使用结果为准。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                SetupCheckRow(check: SetupCheck(id: "waiting", title: model.isCheckingEnvironment ? "正在读取本机环境" : "尚未完成检查", status: .pending,
                                                detail: "点击「检查环境与设备」。Xcode 缺失或尚未完成初始化时，会显示对应处理提示。"))
            }
        }
        Card(title: "2 · 连接与准备 iPhone") {
            SetupCheckRow(check: model.phoneCheck)
            Text("USB 连接 → 解锁 → 信任 Mac → 开启开发者模式。手机上的信任、重启和开发者模式确认需要你本人操作。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("刷新设备") { Task { await model.refresh() } }.disabled(!model.canRefresh)
                Link("Apple 开发者模式说明", destination: URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device")!)
            }
            DeviceCard()
        }
        Card(title: "3 · 选择使用方式") {
            Text("准备就绪后可设置固定坐标，或导入 GPX 到「我的路线」。默认每公里 5分00秒，支持手动修改。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("固定定位") { model.page = .coordinate }
                Button("路线回放") { model.page = .route }
                Button("查看完整帮助") { model.page = .help }
            }
            Text("发布范围：Apple Silicon Mac 通过 USB 控制 iPhone。完整 Xcode 是运行依赖；应用的 macOS 14 最低加载版本不代表所有 macOS 14 设备都能安装所需 Xcode。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SetupCheckRow: View {
    let check: SetupCheck
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.status.icon).font(.title3)
                .foregroundStyle(check.status == .passed ? teal : (check.status == .needsAction ? .orange : Color.secondary))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(check.title).font(.subheadline.weight(.semibold))
                Text(check.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReadinessHint: View {
    @EnvironmentObject var model: AppModel
    var routeMode = false
    var body: some View {
        if model.simulation == nil && !(routeMode ? model.canStartRoute : model.canStart) {
            HStack {
                Label("开始前请完成环境检查和手机开发准备。", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("查看准备步骤") { model.page = .setup }
            }
        }
    }
}

private struct StepView: View {
    let number: String, title: String, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number).font(.system(size: 22, weight: .light, design: .rounded)).foregroundStyle(teal)
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActionCard: View {
    let icon: String, title: String, detail: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon).font(.system(size: 26)).foregroundStyle(color).frame(height: 34)
                HStack { Text(title).font(.title3.weight(.semibold)); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
                Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }.padding(22).frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.16)))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

private struct DeviceCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Card(title: "当前设备") {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: "iphone.gen3").font(.system(size: 38, weight: .light)).foregroundStyle(accent).frame(width: 52)
                VStack(alignment: .leading, spacing: 10) {
                    if !model.phones.isEmpty {
                        Picker("iPhone", selection: $model.selectedID) {
                            if !model.phones.contains(where: { $0.id == model.selectedID }) { Text("选择设备").tag("") }
                            ForEach(model.phones) { phone in Text("\(phone.name) · \(phone.model) · \(phone.stateLabel)").tag(phone.id) }
                        }.labelsHidden().disabled(model.busy || model.simulation != nil)
                        if let phone = model.selectedPhone {
                            HStack(spacing: 16) {
                                Label(phone.stateLabel, systemImage: phone.available ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(phone.available ? teal : .secondary)
                                Text("iOS \(phone.version)")
                                Text("开发者模式：\(phone.developerMode)")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(model.busy ? "正在查找 iPhone…" : "尚未发现 iPhone").font(.headline)
                        Text("USB 连接 → 解锁 → 信任 Mac → 开启开发者模式").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(model.refreshCooldown ? "稍后刷新" : "刷新") { Task { await model.refresh() } }.disabled(!model.canRefresh)
            }
            if model.selectedPhone?.available == false {
                Text("这是已配对的设备记录，目前未连接。接好数据线并解锁后再次刷新。").font(.caption).foregroundStyle(.secondary)
            }
            if model.simulation != nil {
                Text("模拟会话绑定原设备。切换手机前，请先停止并清除。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CoordinatePage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageTitle(eyebrow: "FIXED LOCATION", title: "停留在一个地点", subtitle: "使用 GPS 的 WGS84 经纬度，先纬度、后经度。")
        DeviceCard()
        ReadinessHint()
        if model.simulation != nil { SessionCard() }
        Card(title: "目标坐标") {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("纬度 Latitude").font(.caption).foregroundStyle(.secondary)
                    TextField("例如 37.7749", text: $model.latitude)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("经度 Longitude").font(.caption).foregroundStyle(.secondary)
                    TextField("例如 -122.4194", text: $model.longitude)
                }
            }.textFieldStyle(.roundedBorder).disabled(model.busy || model.simulation != nil)
            HStack {
                Text("纬度 −90～90 · 经度 −180～180").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.startCoordinate() } } label: { Label("应用固定坐标", systemImage: "location.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart)
            }
        }
        Card(title: "坐标说明") {
            Text("固定定位发送位置点，不提供路线移动速度。中国地图常见的 GCJ-02 / BD-09 坐标不能直接当作 WGS84 使用；不同坐标系可能出现偏移。")
                .font(.callout).foregroundStyle(.secondary)
            Text("应用后，请在手机地图点「当前位置」确认蓝点。切换目标前先停止并清除。").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct RoutePage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageTitle(eyebrow: "ROUTE PLAYBACK", title: "沿你的路线移动", subtitle: "导入 GPX，按目标耗时均匀回放。播放一次，到达后保持终点。")
        DeviceCard()
        ReadinessHint(routeMode: true)
        if model.simulation != nil { SessionCard() }
        SavedRoutesCard()
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.route?.name ?? "还没有导入路线").font(.headline).lineLimit(2)
                    Text(model.route == nil ? "在「我的路线」点击选用，或导入新 GPX" : "已保存在路线库 · WGS84")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: URL(string: "https://gpx.studio/zh/app")!) { Image(systemName: "pencil.and.outline"); Text("绘制路线") }
            }
            RoutePreview(route: model.route).frame(height: 245).clipShape(RoundedRectangle(cornerRadius: 12))
            if let route = model.route {
                HStack(spacing: 20) {
                    Metric(title: "路线距离", value: String(format: "%.0f m", route.distance))
                    Metric(title: "每公里用时", value: model.paceSecondsPerKM.map(chinesePace) ?? "—")
                    Metric(title: "计划平均速度", value: model.speed.map { String(format: "%.2f km/h", $0) } ?? "—")
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("总耗时（分:秒，或秒数）").font(.caption).foregroundStyle(.secondary)
                    TextField("导入路线后自动计算", text: $model.durationText).textFieldStyle(.roundedBorder).frame(width: 170)
                        .disabled(model.busy || model.simulation != nil || model.route == nil)
                }
                Button("恢复 5分00秒/公里") { model.resetDuration() }
                    .disabled(model.busy || model.simulation != nil || model.route == nil)
                Spacer()
                Button { Task { await model.startRoute() } } label: { Label("开始单次回放", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!model.canStartRoute || model.route == nil || model.duration == nil)
            }
            if model.route != nil && model.duration == nil { Text("请输入有效时长，例如 11:30 或 690。范围为 1 秒至 24 小时。").font(.caption).foregroundStyle(.orange) }
            Text("默认每公里 5分00秒，总耗时四舍五入到秒。手动修改总耗时后，每公里用时和平均速度会实时更新。").font(.caption).foregroundStyle(.secondary)
            Text("原文件时间戳会被忽略；约每 0.5 秒采样。折点存在轻微近似，实际到达时间以手机为准。启动按钮会直接发送请求。").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SavedRoutesCard: View {
    @EnvironmentObject var model: AppModel
    @State private var pendingDeletion: SavedRoute?
    @State private var showDeletion = false

    var body: some View {
        Card {
            HStack {
                Label("我的路线", systemImage: "tray.full").font(.headline)
                Text("\(model.savedRoutes.count) 条").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.importGPX() } label: { Label("导入 GPX", systemImage: "plus") }
                    .disabled(model.busy || model.simulation != nil)
            }
            if model.savedRoutes.isEmpty {
                Text("导入的路线会保存在这里。下次打开点击选用，也可随时删除。").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.savedRoutes) { entry in
                            SavedRouteRow(entry: entry, selected: model.selectedRouteID == entry.id,
                                          select: { model.selectRoute(entry.id) }, remove: {
                                pendingDeletion = entry
                                showDeletion = true
                            }).disabled(model.busy || model.simulation != nil)
                        }
                    }
                }.frame(height: min(CGFloat(model.savedRoutes.count) * 58, 192))
                Text("点击选用后再开始回放。新导入会添加到列表，相同名称和轨迹重复导入不会新增副本。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .alert("删除已保存的路线？", isPresented: $showDeletion, presenting: pendingDeletion) { entry in
            Button("删除", role: .destructive) { model.deleteRoute(entry.id) }
            Button("取消", role: .cancel) { }
        } message: { entry in
            Text("从路线库移除「\(entry.name)」，软件中的路线副本会移到废纸篓。原始 GPX 文件不受影响。")
        }
    }
}

private struct SavedRouteRow: View {
    let entry: SavedRoute
    let selected: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? accent : Color.secondary)
                    Text(entry.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(entry.distanceLabel).font(.caption).foregroundStyle(.secondary)
                    Text(selected ? "已选用" : "选用").font(.caption.weight(.medium)).foregroundStyle(accent).frame(width: 44)
                }.padding(.vertical, 14).padding(.leading, 14).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: remove) { Image(systemName: "trash").foregroundStyle(.secondary) }
                .buttonStyle(.borderless).padding(.trailing, 14)
                .help("从路线库删除「\(entry.name)」").accessibilityLabel("删除路线 \(entry.name)")
        }
        .background(selected ? accent.opacity(0.07) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent.opacity(0.22) : Color.clear))
    }
}

private struct Metric: View {
    let title: String, value: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RoutePreview: View {
    let route: Route?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                Canvas { context, size in
                    var grid = Path()
                    for x in stride(from: 0.0, through: size.width, by: 28) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
                    for y in stride(from: 0.0, through: size.height, by: 28) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                    context.stroke(grid, with: .color(.secondary.opacity(0.08)), lineWidth: 1)
                    guard let route else { return }
                    // Preview with up to 1,200 evenly spaced samples; source points are kept for playback.
                    let count = min(1200, route.points.count)
                    let points = (0..<count).map { route.point(at: Double($0) / Double(count - 1)) }
                    let origin = points[0]
                    let cosLat = max(0.001, cos(origin.latitude * .pi / 180))
                    let xy = points.map { point -> CGPoint in
                        var delta = point.longitude - origin.longitude
                        if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
                        return CGPoint(x: delta * cosLat, y: -(point.latitude - origin.latitude))
                    }
                    let minX = xy.map(\.x).min()!, maxX = xy.map(\.x).max()!
                    let minY = xy.map(\.y).min()!, maxY = xy.map(\.y).max()!
                    let scale = min((size.width - 60) / max(0.000001, maxX - minX), (size.height - 60) / max(0.000001, maxY - minY))
                    let converted = xy.map { CGPoint(x: ($0.x - (minX + maxX) / 2) * scale + size.width / 2, y: ($0.y - (minY + maxY) / 2) * scale + size.height / 2) }
                    var path = Path(); path.addLines(converted)
                    context.stroke(path, with: .color(teal.opacity(0.14)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(teal), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    for (index, point) in [converted.first!, converted.last!].enumerated() {
                        let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                        context.fill(Path(ellipseIn: rect), with: .color(index == 0 ? accent : .orange))
                        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                    }
                }
                if route == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 38, weight: .light)).foregroundStyle(teal.opacity(0.7))
                        Text("导入后在这里预览路线").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 14) {
                        Label("起点", systemImage: "circle.fill").foregroundStyle(accent)
                        Label("终点", systemImage: "circle.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("形状预览").foregroundStyle(.secondary)
                    }.font(.caption2).padding(12).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}

private struct SessionCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let simulation = model.simulation {
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(model.uncertain ? "模拟状态待确认" : (simulation.kind == "route" ? "路线回放会话" : "固定定位会话"), systemImage: "location.fill")
                            .font(.headline).foregroundStyle(model.uncertain ? .orange : teal)
                        Text(simulation.title).font(.callout).textSelection(.enabled)
                        Text("设备：\(simulation.deviceName)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("停止并清除") { Task { await model.clear() } }.disabled(model.busy)
                }
                if let duration = simulation.duration, !model.uncertain {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let elapsed = max(0, timeline.date.timeIntervalSince(simulation.started))
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: min(elapsed / duration, 1)).tint(teal)
                            HStack {
                                Text(elapsed < duration ? "计划进度 \(clockString(elapsed)) / \(clockString(duration))" : "计划时长已到，请在手机确认是否到达终点")
                                Spacer()
                                Text("估算").foregroundStyle(.secondary)
                            }.font(.caption).monospacedDigit()
                        }
                    }
                }
                Text(model.uncertain ? "软件无法确认当前手机是否仍在模拟。请连接原设备后清除。" : "此状态表示 Xcode 已接受请求，不读取手机实际坐标。保持 Mac 唤醒及手机连接；结束后手动清除。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LogsPage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageTitle(eyebrow: "ACTIVITY", title: "运行日志", subtitle: "保留最近 150 条操作记录，便于排查连接和命令错误。日志仅保存在本机。")
        HStack {
            Button { model.exportLogs() } label: { Label("导出日志", systemImage: "square.and.arrow.up") }
            Spacer()
            Text("日志可能包含设备名称与坐标，分享前请检查。").font(.caption).foregroundStyle(.secondary)
        }
        Card {
            if model.logs.isEmpty { Text("暂无操作记录").foregroundStyle(.secondary) }
            else {
                Text(model.logs.reversed().joined(separator: "\n\n"))
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct HelpPage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageTitle(eyebrow: "SETUP & HELP", title: "准备好你的设备", subtitle: "本软件通过本机 Xcode 开发服务控制 iPhone，不依赖 Codex 会话或旧 Python 环境。")
        Button("打开环境检查与准备步骤") { model.page = .setup }
        Card(title: "Xcode") {
            HStack {
                TextField("Xcode.app 路径", text: $model.xcodePath).textFieldStyle(.roundedBorder).disabled(model.busy || model.simulation != nil)
                Button("选择…") { model.selectXcode() }.disabled(model.busy || model.simulation != nil)
            }
            Label((try? DeviceService.developerDirectory(model.xcodePath)) != nil ? "已找到 devicectl" : "未找到完整 Xcode", systemImage: "hammer")
                .font(.caption).foregroundStyle(.secondary)
            Text("请先手动打开 Xcode，接受许可并完成首次组件安装。当前回放接口来自本机 Xcode 27.1；其他 Xcode / iOS 组合需另行确认。")
                .font(.callout).foregroundStyle(.secondary)
            Button("打开 Xcode") { model.openXcode() }
        }
        Card(title: "iPhone 连接准备") {
            HelpRow(icon: "cable.connector", title: "USB 连接并信任", text: "连接数据线、解锁手机，在 iPhone 上确认「信任此电脑」。同一时间只运行一个定位工具。")
            HelpRow(icon: "hammer", title: "启用开发者模式", text: "在 iPhone「设置 → 隐私与安全性 → 开发者模式」中开启，按系统提示重启并确认。如果找不到开关，可在 Xcode 的 Devices and Simulators 中选择手机，完成开发准备。")
            HelpRow(icon: "arrow.clockwise", title: "刷新设备", text: "回到控制台刷新。列表会同时显示可连接和曾配对的离线设备，只有可连接的设备可以开始模拟。")
        }
        Card(title: "回放与恢复") {
            HelpRow(icon: "tray.full", title: "保存多条路线，点击选用", text: "导入后会添加到「我的路线」，下次点击即可使用。可用每条右侧的删除按钮移除软件内副本，原 GPX 不受影响。原文件移动或删除不影响已保存路线。")
            HelpRow(icon: "play.circle", title: "按配速计算总耗时", text: "默认每公里 5分00秒，手动修改总耗时后会实时显示每公里几分几秒。选用路线时恢复默认配速。播放一次，到达后保持终点；原文件时间戳会被忽略。")
            HelpRow(icon: "stop.circle", title: "结束后清除", text: "先在记录软件里结束记录，再点「停止并清除」。清除命令成功返回后，还需在手机地图确认真实位置；如果仍残留，重启 iPhone。拔线不保证恢复。")
            HelpRow(icon: "waveform.path", title: "系统字段的限制", text: "路线接口曾测得非负 speed，但 speedAccuracy 仍可能为 −1，软件模拟来源标记仍存在。第三方 App 是否累计里程取决于其规则，软件不保证。")
        }
        Card(title: "资料与本机数据") {
            HStack(spacing: 16) {
                Link("打开 GPX 绘制网站", destination: URL(string: "https://gpx.studio/zh/app")!)
                Button("完整使用说明") { model.openDocumentation() }
                Button("打开数据目录") { NSWorkspace.shared.open(DeviceService.support) }
            }
            Text("数据目录保存路线库、日志、当前会话与回放坐标文件。GPX 预览和重采样在本机完成。本软件不直接读取第三方运动 App 的代码或记录。")
                .font(.caption).foregroundStyle(.secondary)
            Text("定位诊断是单独的 iPhone App。完整项目源码包内附有其源码；需要通过 Xcode 单独签名安装。").font(.caption).foregroundStyle(.secondary)
        }
        Text("定位控制台 1.3.0 Beta 1 · Apple Silicon · 需要兼容的完整 Xcode").font(.caption).foregroundStyle(.secondary)
    }
}

private struct HelpRow: View {
    let icon: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(teal).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
