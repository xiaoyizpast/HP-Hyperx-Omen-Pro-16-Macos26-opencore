import Cocoa
import IOKit
import IOKit.ps

// MARK: - 数据

struct Snapshot {
    var fan1 = 0, fan2 = 0, cpu = 0, gpu = 0
    var memUsedGB = 0.0, memTotalGB = 0.0
    var vramUsedMB = 0.0, vramTotalMB = 8192.0
    var gpuUtil = 0
    var load1 = 0.0
    var cpuMHz = 0.0
    var cpuW = 0.0
    var onAC = true
    var batteryPct = -1
    var ok = false
}

let gPageSize: Double = {
    var sz: vm_size_t = 0
    host_page_size(mach_host_self(), &sz)
    return Double(sz)
}()

func memUsedGB() -> (Double, Double) {
    let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return (0, total) }
    let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
    return (used * gPageSize / 1_073_741_824, total)
}

func gpuStats() -> (Int, Double) {
    var util = 0; var vram = 0.0
    var iter: io_iterator_t = 0
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS {
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                if let ps = dict["PerformanceStatistics"] as? [String: Any],
                   let u = ps["Device Utilization %"] as? Int { util = max(util, u) }
                if let acc = dict["PerformanceStatisticsAccum"] as? [String: Any],
                   let b = acc["inUseVidMemoryBytes"] as? Int { vram = max(vram, Double(b) / 1_048_576) }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
    }
    return (util, vram)
}

func gpuTempFromEC() -> Int {
    var size = 0
    guard sysctlbyname("kern.ecdump1", nil, &size, nil, 0) == 0, size > 0 else { return 0 }
    var buf = [CChar](repeating: 0, count: size + 1)
    guard sysctlbyname("kern.ecdump1", &buf, &size, nil, 0) == 0 else { return 0 }
    for line in String(cString: buf).split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count >= 17, parts[0].hasPrefix("B0:") else { continue }
        let idx = 0xB7 - 0xB0
        if parts.count > idx + 1, let v = Int(parts[idx + 1], radix: 16) { return v }
    }
    return 0
}

func batteryInfo() -> (Bool, Int) {
    var pct = -1
    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
               let cap = d[kIOPSCurrentCapacityKey] as? Int,
               let maxc = d[kIOPSMaxCapacityKey] as? Int, maxc > 0 { pct = cap * 100 / maxc }
        }
    }
    var onAC = true
    if let t = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as? String { onAC = (t == "AC Power") }
    return (onAC, pct)
}

func readFan() -> Snapshot {
    var s = Snapshot()
    var size = 0
    guard sysctlbyname("kern.ecfan", nil, &size, nil, 0) == 0, size > 0 else { return s }
    var buf = [CChar](repeating: 0, count: size + 1)
    guard sysctlbyname("kern.ecfan", &buf, &size, nil, 0) == 0 else { return s }
    for part in String(cString: buf).split(separator: " ") {
        let kv = part.split(separator: "=")
        guard kv.count == 2 else { continue }
        let v = Int(kv[1]) ?? 0
        switch String(kv[0]) {
        case "fan1": s.fan1 = v
        case "fan2": s.fan2 = v
        case "cpu": s.cpu = v
        case "gpu": s.gpu = v
        default: break
        }
    }
    s.ok = true
    return s
}

func readCPUMHz() -> Double {
    var size = 0
    guard sysctlbyname("kern.cpufreq", nil, &size, nil, 0) == 0, size > 0 else { return 0 }
    var buf = [CChar](repeating: 0, count: size + 1)
    guard sysctlbyname("kern.cpufreq", &buf, &size, nil, 0) == 0 else { return 0 }
    return Double(String(cString: buf)) ?? 0
}

func readCPUPower() -> Double {
    var size = 0
    guard sysctlbyname("kern.cpupower", nil, &size, nil, 0) == 0, size > 0 else { return 0 }
    var buf = [CChar](repeating: 0, count: size + 1)
    guard sysctlbyname("kern.cpupower", &buf, &size, nil, 0) == 0 else { return 0 }
    return Double(String(cString: buf)) ?? 0
}

func sample() -> Snapshot {
    var s = readFan()
    (s.memUsedGB, s.memTotalGB) = memUsedGB()
    (s.gpuUtil, s.vramUsedMB) = gpuStats()
    var loads = [Double](repeating: 0, count: 3)
    getloadavg(&loads, 3)
    s.load1 = loads[0]
    (s.onAC, s.batteryPct) = batteryInfo()
    s.cpuMHz = readCPUMHz()
    s.cpuW = readCPUPower()
    return s
}

// MARK: - EPP / CPB

var gUC: io_connect_t = 0

func eppConnection() -> io_connect_t {
    if gUC != 0 { return gUC }
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AMDRyzenCPUPowerManagement"))
    guard svc != 0 else { return 0 }
    var c: io_connect_t = 0
    if IOServiceOpen(svc, mach_task_self_, 0, &c) == KERN_SUCCESS { gUC = c }
    IOObjectRelease(svc)
    return gUC
}

func eppCall(_ sel: UInt32, _ input: UInt64?) -> kern_return_t {
    let conn = eppConnection()
    guard conn != 0 else { return KERN_FAILURE }
    var out = [UInt64](repeating: 0, count: 8)
    var cnt: UInt32 = 8
    if let iv = input {
        var v = iv
        return IOConnectCallScalarMethod(conn, sel, &v, 1, &out, &cnt)
    }
    return IOConnectCallScalarMethod(conn, sel, nil, 0, &out, &cnt)
}

func eppStatus() -> (UInt64, UInt64) {
    let conn = eppConnection()
    guard conn != 0 else { return (0, 0) }
    var out = [UInt64](repeating: 0, count: 8)
    var cnt: UInt32 = 8
    if IOConnectCallScalarMethod(conn, 23, nil, 0, &out, &cnt) != KERN_SUCCESS { return (0, 0) }
    return (out[0], out[1])
}

func applyEPPPreset(_ p: Int) -> Bool {
    if p <= 0 { return eppCall(24, 0) == KERN_SUCCESS }
    let vals: [UInt64] = [0, 0, 64, 128, 192, 255]
    guard eppCall(24, 1) == KERN_SUCCESS else { return false }
    return eppCall(25, vals[min(p, 5)]) == KERN_SUCCESS
}

func setCPBDisabled(_ off: Bool) -> Bool { eppCall(12, off ? 0 : 1) == KERN_SUCCESS }

func setFan(_ v: String) -> Bool {
    v.withCString { p in
        sysctlbyname("kern.ecfan_set", nil, nil, UnsafeMutableRawPointer(mutating: p), strlen(p)) == 0
    }
}

// MARK: - 主题

struct Theme {
    var bg: NSColor { .windowBackgroundColor }
    var card: NSColor { .controlBackgroundColor }
    var text: NSColor { .labelColor }
    var sub: NSColor { .secondaryLabelColor }
    var accent: NSColor { .controlAccentColor }
    var grid: NSColor { .separatorColor }
    static let dark = Theme()
    static let light = Theme()
}

func resolvedCG(_ color: NSColor, _ view: NSView) -> CGColor {
    var cg = color.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
    return cg
}

// MARK: - 折线图

final class LineChart: NSView {
    var theme: Theme = .dark
    var title: String = ""
    var series: [Double] = []
    var suffix = ""
    var fixedMax: Double? = nil
    var color: NSColor = .systemBlue

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        let r = NSRect(x: 10, y: 24, width: bounds.width - 20, height: bounds.height - 40)
        // 网格
        theme.grid.setStroke()
        for i in 0...4 {
            let y = r.minY + r.height * CGFloat(i) / 4
            let p = NSBezierPath(); p.move(to: NSPoint(x: r.minX, y: y)); p.line(to: NSPoint(x: r.maxX, y: y)); p.stroke()
        }
        let maxV = fixedMax ?? max(series.max() ?? 1, 1)
        if series.count > 1 {
            let path = NSBezierPath()
            for (i, v) in series.enumerated() {
                let x = r.minX + r.width * CGFloat(i) / CGFloat(max(series.count - 1, 1))
                let y = r.minY + r.height * CGFloat(min(v / maxV, 1))
                if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
            }
            color.setStroke(); path.lineWidth = 1.8; path.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: theme.sub, .font: NSFont.systemFont(ofSize: 11)]
        (title as NSString).draw(at: NSPoint(x: 12, y: bounds.height - 18), withAttributes: attrs)
        let last = series.last ?? 0
        let vattrs: [NSAttributedString.Key: Any] = [.foregroundColor: theme.text, .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
        (String(format: "%.0f", last) + suffix as NSString).draw(at: NSPoint(x: bounds.width - 70, y: bounds.height - 18), withAttributes: vattrs)
        let mattrs: [NSAttributedString.Key: Any] = [.foregroundColor: theme.sub, .font: NSFont.systemFont(ofSize: 9)]
        (String(format: "max %.0f", maxV) as NSString).draw(at: NSPoint(x: 12, y: 4), withAttributes: mattrs)
    }
}

// MARK: - 曲线编辑

protocol CurveDelegate: AnyObject { func curveChanged() }

final class CurveView: NSView {
    weak var delegate: CurveDelegate?
    var theme: Theme = .dark
    var points: [CGPoint] = [CGPoint(x: 45, y: 40), CGPoint(x: 60, y: 55), CGPoint(x: 75, y: 75), CGPoint(x: 92, y: 100)]
    private var dragIndex: Int? = nil
    private func plot(_ r: NSRect) -> NSRect { NSRect(x: r.minX + 40, y: r.minY + 26, width: r.width - 60, height: r.height - 50) }
    private func toScreen(_ p: CGPoint, _ r: NSRect) -> NSPoint {
        let pr = plot(r)
        return NSPoint(x: pr.minX + CGFloat((p.x - 30) / 70) * pr.width, y: pr.minY + CGFloat((p.y - 30) / 70) * pr.height)
    }
    private func toValue(_ s: NSPoint, _ r: NSRect) -> CGPoint {
        let pr = plot(r)
        var tx = (s.x - pr.minX) / pr.width * 70 + 30
        var ty = (s.y - pr.minY) / pr.height * 70 + 30
        tx = min(max(tx, 30), 100); ty = min(max(ty, 30), 100)
        return CGPoint(x: tx.rounded(), y: ty.rounded())
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        let pr = plot(bounds)
        theme.grid.setStroke()
        for i in 0...6 {
            let x = pr.minX + pr.width * CGFloat(i) / 6
            let y = pr.minY + pr.height * CGFloat(i) / 6
            let px = NSBezierPath(); px.move(to: NSPoint(x: x, y: pr.minY)); px.line(to: NSPoint(x: x, y: pr.maxY)); px.stroke()
            let py = NSBezierPath(); py.move(to: NSPoint(x: pr.minX, y: y)); py.line(to: NSPoint(x: pr.maxX, y: y)); py.stroke()
        }
        let sorted = points.sorted { $0.x < $1.x }
        let path = NSBezierPath()
        for (i, p) in sorted.enumerated() {
            let s = toScreen(p, bounds)
            if i == 0 { path.move(to: s) } else { path.line(to: s) }
        }
        theme.accent.setStroke(); path.lineWidth = 2.5; path.stroke()
        for p in sorted {
            let s = toScreen(p, bounds)
            let dot = NSBezierPath(ovalIn: NSRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10))
            theme.accent.setFill(); dot.fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: theme.sub, .font: NSFont.systemFont(ofSize: 10)]
        for i in stride(from: 30, through: 100, by: 10) {
            let x = pr.minX + pr.width * CGFloat(i - 30) / 70
            ("\(i)" as NSString).draw(at: NSPoint(x: x - 8, y: pr.minY - 15), withAttributes: attrs)
        }
    }
    override func mouseDown(with event: NSEvent) {
        let s = convert(event.locationInWindow, from: nil)
        var best: (Int, CGFloat)? = nil
        for (i, p) in points.enumerated() {
            let sp = toScreen(p, bounds)
            let d = hypot(sp.x - s.x, sp.y - s.y)
            if d < 14, best == nil || d < best!.1 { best = (i, d) }
        }
        dragIndex = best?.0
    }
    override func mouseDragged(with event: NSEvent) {
        guard let i = dragIndex else { return }
        points[i] = toValue(convert(event.locationInWindow, from: nil), bounds)
        needsDisplay = true
        delegate?.curveChanged()
    }
    override func mouseUp(with event: NSEvent) { dragIndex = nil }
}

// MARK: - 控件

final class StatCard: NSView {
    var nameLabel: NSTextField!
    var valueLabel: NSTextField!
    init(name: String) {
        super.init(frame: .zero)
        nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.frame = NSRect(x: 10, y: 32, width: 160, height: 14)
        addSubview(nameLabel)
        valueLabel = NSTextField(labelWithString: "--")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.frame = NSRect(x: 10, y: 8, width: 170, height: 22)
        addSubview(valueLabel)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = resolvedCG(NSColor.controlBackgroundColor, self)
        nameLabel.textColor = .secondaryLabelColor
        valueLabel.textColor = .labelColor
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
    func apply(_ t: Theme) {
        nameLabel.textColor = .secondaryLabelColor
        valueLabel.textColor = .labelColor
    }
}

// MARK: - 调试日志

let logDir = NSHomeDirectory() + "/Library/Logs/FanControl"
let logPath = logDir + "/debug.log"

func debugLog(_ msg: String) {
    guard UserDefaults.standard.bool(forKey: "debugMode") else { return }
    let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
    let line = "[\(df.string(from: Date()))] \(msg)\n"
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

final class ThemedView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        wantsLayer = true
        layer?.backgroundColor = resolvedCG(NSColor.windowBackgroundColor, self)
    }
}

// MARK: - 侧栏行

final class SidebarRow: NSView {
    let iconView = NSImageView()
    let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var onDrop: ((SidebarRow) -> Void)?
    private var dragStart: NSPoint?
    private var originY: CGFloat = 0
    private var moved = false
    var selected = false {
        didSet {
            needsDisplay = true
            label.textColor = selected ? .labelColor : .secondaryLabelColor
            iconView.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
        }
    }
    init(title: String, symbol: String) {
        super.init(frame: .zero)
        wantsLayer = true
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        addSubview(iconView)
        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 14, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 38, y: (bounds.height - 17) / 2, width: bounds.width - 48, height: 17)
    }
    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        originY = frame.origin.y
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let s = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dy = p.y - s.y
        if abs(dy) > 4 { moved = true }
        if moved { frame.origin.y = originY + dy }
    }
    override func mouseUp(with event: NSEvent) {
        if moved { onDrop?(self) } else { onClick?() }
        dragStart = nil; moved = false
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, CurveDelegate {
    var window: NSWindow!
    var content: NSView!
    var sidebar: NSView!
    var theme: Theme = .dark
    var snapshot = Snapshot()
    var timer: Timer?
    var currentPage = 0
    var sideRows: [SidebarRow] = []
    var sidePages: [Int] = []
    var pageOrder: [Int] = [0, 1, 2, 3]

    var cards: [String: StatCard] = [:]
    var chartCPU: LineChart!, chartFan: LineChart!, chartGPU: LineChart!
    var cpuHist: [Double] = [], fanHist: [Double] = [], gpuHist: [Double] = []

    var eppPopup: NSPopUpButton!
    var cpbToggle: NSButton!
    var batteryToggle: NSButton!
    var perfState: NSTextField!

    var curveView: CurveView!
    var curveToggle: NSButton!
    var fanState: NSTextField!
    var lastApplied = -1

    var themeSegment: NSSegmentedControl!
    var autoStartToggle: NSButton!
    var debugToggle: NSButton!
    var envLabel: NSTextField!
    var statusItem: NSStatusItem?
    var appearanceMode: String = "system"
    var appearanceSegment: NSSegmentedControl!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSSetUncaughtExceptionHandler { ex in
            debugLog("CRASH: \(ex.name.rawValue) \(ex.reason ?? "")")
        }
        appearanceMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        appearanceMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"

        let rect = NSRect(x: 0, y: 0, width: 980, height: 620)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Zfan"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center(); window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ZfanMainWindow")
        window.minSize = NSSize(width: 900, height: 580)

        let root = NSView(frame: rect); root.wantsLayer = true
        window.contentView = root
        let sideW: CGFloat = 200
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sideW, height: rect.height))
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.autoresizingMask = [.height]
        sidebar = effect
        root.addSubview(sidebar)

        buildSidebarRows()

        content = NSView(frame: NSRect(x: sideW, y: 0, width: rect.width - sideW, height: rect.height))
        content.autoresizingMask = [.width, .height]
        root.addSubview(content)

        if let saved = UserDefaults.standard.array(forKey: "pageOrderArray") as? [Int], saved.count == 4, Set(saved).count == 4 {
            pageOrder = saved
        }
        buildOverview(); buildPerformance(); buildFan(); buildSettings()
        setupStatusItem()
        showPage(0); applyAppearance()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            if let w = e.window, let cv = w.contentView {
                let pt = cv.convert(e.locationInWindow, from: nil)
                let hit = cv.hitTest(pt)
                debugLog("click \(Int(pt.x)),\(Int(pt.y)) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            }
            return e
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in self.tick() }
        tick()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func loadSettings() {
        let d = UserDefaults.standard
        let p = d.object(forKey: "eppPreset") as? Int ?? 0
        eppPopup.selectItem(at: min(max(p, 0), 5))
        cpbToggle.state = d.bool(forKey: "cpbOff") ? .on : .off
        batteryToggle.state = d.bool(forKey: "batteryAuto") ? .on : .off
        curveToggle.state = d.bool(forKey: "curveOn") ? .on : .off
        if let pts = d.array(forKey: "curve") as? [[Double]], pts.count == 4 {
            curveView.points = pts.map { CGPoint(x: $0[0], y: $0[1]) }
            curveView.needsDisplay = true
        }
        debugLog("settings loaded: epp=\(p) cpb=\(cpbToggle.state == .on) battery=\(batteryToggle.state == .on) curve=\(curveToggle.state == .on)")
    }

    func applySavedState() {
        _ = applyEPPPreset(eppPopup.indexOfSelectedItem)
        _ = setCPBDisabled(cpbToggle.state == .on)
        if curveToggle.state == .on {
            tick()
        } else if let p = UserDefaults.standard.string(forKey: "fanPreset"), p != "auto" {
            _ = setFan(p)
        }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem?.button {
            b.image = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "Zfan")
            b.image?.isTemplate = true
        }
        let m = NSMenu()
        m.addItem(NSMenuItem(title: "显示窗口", action: #selector(showWindow), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "退出 Zfan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = m
        updateStatusBar(snapshot)
    }

    @objc func openSettings() {
        showPage(3)
        showWindow()
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateStatusBar(_ s: Snapshot) {
        var parts: [String] = []
        let d = UserDefaults.standard
        if d.bool(forKey: "sb_cpu") { parts.append("\(s.cpu)°C") }
        if d.bool(forKey: "sb_gpu"), snapshot.gpu > 0 { parts.append("G\(snapshot.gpu)°") }
        if d.bool(forKey: "sb_fan") { parts.append("\(s.fan1)") }
        if d.bool(forKey: "sb_freq"), s.cpuMHz > 0 { parts.append(String(format: "%.1fG", s.cpuMHz / 1000)) }
        if d.bool(forKey: "sb_mem") { parts.append(String(format: "%.0f%%", s.memUsedGB / max(s.memTotalGB, 1) * 100)) }
        statusItem?.button?.title = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    let pageMeta = [("总览", "gauge"), ("性能", "speedometer"), ("风扇", "fanblades"), ("设置", "gearshape")]

    func buildSidebarRows() {
        for r in sideRows { r.removeFromSuperview() }
        sideRows.removeAll()
        var y = window.frame.height - 110
        sidePages.removeAll()
        for pageIdx in pageOrder where pageIdx != 3 {
            let meta = pageMeta[pageIdx]
            let row = SidebarRow(title: meta.0, symbol: meta.1)
            row.frame = NSRect(x: 8, y: y, width: (sidebar.frame.width) - 16, height: 30)
            row.onClick = { [weak self] in self?.showPage(pageIdx) }
            row.onDrop = { [weak self] r in self?.dropRow(r) }
            sidebar.addSubview(row)
            sideRows.append(row); sidePages.append(pageIdx)
            y -= 34
        }
        let srow = SidebarRow(title: "设置", symbol: "gearshape")
        srow.frame = NSRect(x: 8, y: 16, width: sidebar.frame.width - 16, height: 30)
        srow.onClick = { [weak self] in self?.showPage(3) }
        sidebar.addSubview(srow)
        sideRows.append(srow); sidePages.append(3)
        for (i, r) in sideRows.enumerated() { r.selected = (sidePages[i] == currentPage) }
        debugLog("sidebar subviews=\(sidebar.subviews.count) rows=\(sideRows.map { "\($0.frame)" })")
    }

    func dropRow(_ row: SidebarRow) {
        let mains = sideRows.filter { $0 !== sideRows.last }
        let sorted = mains.sorted { $0.frame.midY > $1.frame.midY }
        var order: [Int] = []
        for r in sorted {
            if let idx = sideRows.firstIndex(of: r), idx < sidePages.count { order.append(sidePages[idx]) }
        }
        if Set(order).count == 3 {
            pageOrder = order + [3]
            UserDefaults.standard.set(pageOrder, forKey: "pageOrderArray")
        }
        buildSidebarRows()
    }

    // MARK: 总览（左统计，右图表）

    func buildOverview() {
        let v = NSView(frame: content.bounds); v.autoresizingMask = [.width, .height]; v.identifier = NSUserInterfaceItemIdentifier("p0")
        let W = content.bounds.width
        let leftW = W * 0.46, rightX = leftW + 20, rightW = W - rightX - 20

        let logo = NSImageView(frame: NSRect(x: 16, y: 552, width: 40, height: 40))
        logo.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: nil)
        v.addSubview(logo)
        let name = NSTextField(labelWithString: "Zfan")
        name.font = .systemFont(ofSize: 22, weight: .bold)
        name.frame = NSRect(x: 64, y: 566, width: 200, height: 26); v.addSubview(name)
        let sub = NSTextField(labelWithString: "HP HyperX OMEN PRO 16")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.frame = NSRect(x: 64, y: 548, width: 260, height: 16); v.addSubview(sub)

        let defs: [(String, String)] = [("cpu", "CPU 温度"), ("gpu", "GPU 温度"), ("fan1", "左风扇"),
                                        ("fan2", "右风扇"), ("mem", "内存"), ("vram", "显存"),
                                        ("load", "系统负载"), ("power", "电源"), ("freq", "CPU 频率"),
                                        ("cpuw", "CPU 功耗"), ("gpuw", "GPU 功耗")]
        let cw = (leftW - 30) / 2, ch: CGFloat = 58
        for (i, d) in defs.enumerated() {
            let c = StatCard(name: d.1)
            let col = i % 2, row = i / 2
            c.frame = NSRect(x: 16 + CGFloat(col) * (cw + 10), y: 470 - CGFloat(row) * (ch + 6), width: cw, height: ch)
            v.addSubview(c); cards[d.0] = c
        }

        chartCPU = LineChart(frame: NSRect(x: rightX, y: 410, width: rightW, height: 130))
        chartCPU.title = "CPU 温度"; chartCPU.suffix = "°C"; chartCPU.color = .systemOrange
        chartGPU = LineChart(frame: NSRect(x: rightX, y: 265, width: rightW, height: 130))
        chartGPU.title = "GPU 温度"; chartGPU.suffix = "°C"; chartGPU.color = .systemRed
        chartFan = LineChart(frame: NSRect(x: rightX, y: 120, width: rightW, height: 130))
        chartFan.title = "风扇转速"; chartFan.suffix = " RPM"; chartFan.color = .systemBlue
        for c in [chartCPU!, chartGPU!, chartFan!] { v.addSubview(c) }

        content.addSubview(v)
    }

    // MARK: 性能

    func buildPerformance() {
        let v = NSView(frame: content.bounds); v.autoresizingMask = [.width, .height]; v.identifier = NSUserInterfaceItemIdentifier("p1")
        let l1 = NSTextField(labelWithString: "CPU 加速偏好（EPP）")
        l1.font = .systemFont(ofSize: 14, weight: .medium)
        l1.frame = NSRect(x: 30, y: 500, width: 260, height: 20); v.addSubview(l1)
        eppPopup = NSPopUpButton(frame: NSRect(x: 30, y: 460, width: 220, height: 28))
        eppPopup.addItems(withTitles: ["关闭（不限制）", "性能（0）", "偏性能（64）", "平衡（128）", "偏省电（192）", "省电（255）"])
        eppPopup.target = self; eppPopup.action = #selector(eppChanged)
        v.addSubview(eppPopup)
        cpbToggle = NSButton(checkboxWithTitle: "关闭 CPU 加速（CPB，上限≈基频）", target: self, action: #selector(cpbChanged))
        cpbToggle.frame = NSRect(x: 30, y: 415, width: 360, height: 22); v.addSubview(cpbToggle)
        batteryToggle = NSButton(checkboxWithTitle: "电池时自动省电（EPP 255 + 关 CPB）", target: self, action: #selector(batteryChanged))
        batteryToggle.frame = NSRect(x: 30, y: 385, width: 380, height: 22); v.addSubview(batteryToggle)
        perfState = NSTextField(labelWithString: "")
        perfState.font = .systemFont(ofSize: 12)
        perfState.frame = NSRect(x: 30, y: 345, width: 500, height: 20); v.addSubview(perfState)
        content.addSubview(v)
    }

    // MARK: 风扇

    func buildFan() {
        let v = NSView(frame: content.bounds); v.autoresizingMask = [.width, .height]; v.identifier = NSUserInterfaceItemIdentifier("p2")
        let presets: [(String, String)] = [("安静 45%", "45"), ("平衡 65%", "65"), ("狂暴 100%", "100"), ("自动", "auto")]
        var x: CGFloat = 24
        for (t, id) in presets {
            let b = NSButton(title: t, target: self, action: #selector(fanPreset(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(id); b.bezelStyle = .rounded
            b.frame = NSRect(x: x, y: 520, width: 110, height: 32); v.addSubview(b); x += 120
        }
        curveToggle = NSButton(checkboxWithTitle: "启用手动曲线", target: self, action: #selector(curveToggled))
        curveToggle.frame = NSRect(x: 24, y: 486, width: 200, height: 22); v.addSubview(curveToggle)
        curveView = CurveView(frame: NSRect(x: 20, y: 60, width: content.bounds.width - 40, height: 410))
        curveView.delegate = self; v.addSubview(curveView)
        fanState = NSTextField(labelWithString: "")
        fanState.font = .systemFont(ofSize: 12)
        fanState.frame = NSRect(x: 24, y: 24, width: 600, height: 20); v.addSubview(fanState)
        content.addSubview(v)
    }

    // MARK: 设置页

    func buildSettings() {
        let v = NSView(frame: content.bounds); v.autoresizingMask = [.width, .height]; v.identifier = NSUserInterfaceItemIdentifier("p3")
        autoStartToggle = NSButton(checkboxWithTitle: "登录时自动启动并接管风扇", target: self, action: #selector(autoStartChanged))
        autoStartToggle.frame = NSRect(x: 30, y: 470, width: 340, height: 22)
        autoStartToggle.state = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/LaunchAgents/com.local.fancontrol.plist") ? .on : .off
        v.addSubview(autoStartToggle)

        debugToggle = NSButton(checkboxWithTitle: "调试模式（记录运行日志）", target: self, action: #selector(debugChanged))
        debugToggle.frame = NSRect(x: 30, y: 440, width: 340, height: 22)
        debugToggle.state = UserDefaults.standard.bool(forKey: "debugMode") ? .on : .off
        v.addSubview(debugToggle)

        let apLabel = NSTextField(labelWithString: "外观")
        apLabel.frame = NSRect(x: 30, y: 520, width: 60, height: 20); v.addSubview(apLabel)
        appearanceSegment = NSSegmentedControl(labels: ["跟随系统", "浅色", "深色"], trackingMode: .selectOne,
                                               target: self, action: #selector(appearanceChanged(_:)))
        appearanceSegment.frame = NSRect(x: 100, y: 516, width: 260, height: 26)
        appearanceSegment.selectedSegment = (appearanceMode == "light") ? 1 : (appearanceMode == "dark" ? 2 : 0)
        v.addSubview(appearanceSegment)

        let sbTitle = NSTextField(labelWithString: "状态栏显示")
        sbTitle.font = .systemFont(ofSize: 13, weight: .medium)
        sbTitle.frame = NSRect(x: 30, y: 360, width: 200, height: 18); v.addSubview(sbTitle)

        let sbItems: [(String, String)] = [("sb_cpu", "CPU 温度"), ("sb_gpu", "GPU 温度"), ("sb_fan", "风扇转速"),
                                           ("sb_freq", "CPU 频率"), ("sb_mem", "内存占用")]
        var sx: CGFloat = 30, sy: CGFloat = 332
        for (key, title) in sbItems {
            let cb = NSButton(checkboxWithTitle: title, target: self, action: #selector(sbToggle(_:)))
            cb.identifier = NSUserInterfaceItemIdentifier(key)
            cb.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
            cb.frame = NSRect(x: sx, y: sy, width: 160, height: 20)
            v.addSubview(cb)
            sx += 170
            if sx > 430 { sx = 30; sy -= 26 }
        }

        let checkBtn = NSButton(title: "运行环境检查", target: self, action: #selector(envCheck))
        checkBtn.frame = NSRect(x: 30, y: 270, width: 130, height: 28); v.addSubview(checkBtn)
        let diagBtn = NSButton(title: "导出诊断包", target: self, action: #selector(exportDiagnostics))
        diagBtn.frame = NSRect(x: 172, y: 270, width: 130, height: 28); v.addSubview(diagBtn)

        envLabel = NSTextField(labelWithString: "")
        envLabel.font = .systemFont(ofSize: 11)
        envLabel.frame = NSRect(x: 30, y: 120, width: 700, height: 130)
        envLabel.lineBreakMode = .byWordWrapping
        envLabel.maximumNumberOfLines = 7
        v.addSubview(envLabel)

        let author = NSTextField(labelWithString: "作者：xiaoyizpast · MIT License · Zfan 2.0.0")
        author.font = .systemFont(ofSize: 11)
        author.frame = NSRect(x: 30, y: 30, width: 500, height: 18); v.addSubview(author)
        content.addSubview(v)
    }

    // MARK: 交互

    @objc func switchPage(_ sender: NSButton) { showPage(sender.tag) }

    func showPage(_ i: Int) {
        currentPage = max(0, min(i, 3))
        for sub in content.subviews { sub.isHidden = (sub.identifier?.rawValue != "p\(currentPage)") }
        for (i, r) in sideRows.enumerated() where i < sidePages.count { r.selected = (sidePages[i] == currentPage) }
        window.title = "Zfan · " + ["总览", "性能", "风扇", "设置"][currentPage]
        debugLog("page -> \(currentPage)")
    }

    @objc func fanPreset(_ sender: NSButton) {
        let id = sender.identifier?.rawValue ?? "auto"
        curveToggle.state = .off
        if id == "auto" { _ = setFan("auto") } else { _ = setFan(id); lastApplied = Int(id) ?? 0 }
        UserDefaults.standard.set(id, forKey: "fanPreset")
        debugLog("fan preset \(id)")
    }

    @objc func curveToggled() {
        UserDefaults.standard.set(curveToggle.state == .on, forKey: "curveOn")
        if curveToggle.state == .off { _ = setFan("auto") }
        tick()
    }

    func curveChanged() {
        UserDefaults.standard.set(curveView.points.map { [Double($0.x), Double($0.y)] }, forKey: "curve")
    }

    func curveValue(for temp: Int) -> Int {
        let pts = curveView.points.sorted { $0.x < $1.x }
        if temp <= Int(pts.first!.x) { return max(30, Int(pts.first!.y)) }
        if temp >= Int(pts.last!.x) { return min(100, Int(pts.last!.y)) }
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            if CGFloat(temp) >= a.x && CGFloat(temp) <= b.x {
                let t = (CGFloat(temp) - a.x) / (b.x - a.x)
                return max(30, min(100, Int(a.y + (b.y - a.y) * t)))
            }
        }
        return 50
    }

    @objc func eppChanged() {
        _ = applyEPPPreset(eppPopup.indexOfSelectedItem)
        UserDefaults.standard.set(eppPopup.indexOfSelectedItem, forKey: "eppPreset")
        debugLog("epp preset \(eppPopup.indexOfSelectedItem)")
    }
    @objc func cpbChanged() {
        _ = setCPBDisabled(cpbToggle.state == .on)
        UserDefaults.standard.set(cpbToggle.state == .on, forKey: "cpbOff")
        debugLog("cpb off=\(cpbToggle.state == .on)")
    }
    @objc func batteryChanged() {
        UserDefaults.standard.set(batteryToggle.state == .on, forKey: "batteryAuto")
    }

    @objc func debugChanged() {
        UserDefaults.standard.set(debugToggle.state == .on, forKey: "debugMode")
        debugLog("debug mode \(debugToggle.state == .on)")
    }

    @objc func autoStartChanged() {
        let path = NSHomeDirectory() + "/Library/LaunchAgents/com.local.fancontrol.plist"
        if autoStartToggle.state == .on {
            let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.local.fancontrol</string>
<key>ProgramArguments</key><array><string>/Applications/Fan Control.app/Contents/MacOS/FanControl</string></array>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
"""
            try? plist.write(toFile: path, atomically: true, encoding: .utf8)
            run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", path])
        } else {
            run("/bin/launchctl", ["bootout", "gui/\(getuid())", path])
            try? FileManager.default.removeItem(atPath: path)
        }
        debugLog("autostart \(autoStartToggle.state == .on)")
    }

    func run(_ tool: String, _ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        try? p.run()
    }

    @objc func appearanceChanged(_ s: NSSegmentedControl) {
        appearanceMode = s.selectedSegment == 1 ? "light" : (s.selectedSegment == 2 ? "dark" : "system")
        UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode")
        applyAppearance()
    }

    @objc func sbToggle(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
        updateStatusBar(snapshot)
        debugLog("statusbar \(key)=\(sender.state == .on)")
    }

    @objc func envCheck() {
        var lines: [String] = []
        lines.append(sysctlbyname("kern.ecfan", nil, nil, nil, 0) == 0 ? "✅ EC kext 已加载" : "❌ EC kext 未加载")
        lines.append(eppConnection() != 0 ? "✅ AMD 电源管理接口可用" : "❌ AMD 电源管理接口不可用")
        lines.append(FileManager.default.fileExists(atPath: "/Applications/Fan Control.app") ? "✅ App 已安装" : "❌ App 未在 /Applications")
        lines.append(FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/LaunchAgents/com.local.fancontrol.plist") ? "✅ 自启已配置" : "⚠️ 自启未配置")
        envLabel.stringValue = lines.joined(separator: "\n")
        debugLog("env check: \(lines.joined(separator: " | "))")
    }

    @objc func exportDiagnostics() {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "FanControl-diagnostics-\(df.string(from: Date()))"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        var report = "Fan Control diagnostics\n"
        report += "date: \(Date())\n"
        report += "version: 1.7.0\n"
        report += "theme: \(UserDefaults.standard.string(forKey: "theme") ?? "dark")\n"
        report += "debug: \(UserDefaults.standard.bool(forKey: "debugMode"))\n"
        report += "snapshot: fan1=\(snapshot.fan1) fan2=\(snapshot.fan2) cpu=\(snapshot.cpu) gpu=\(snapshot.gpu) mem=\(snapshot.memUsedGB)/\(snapshot.memTotalGB) vram=\(snapshot.vramUsedMB) load=\(snapshot.load1) ac=\(snapshot.onAC)\n"
        report += "\n--- kern.ecfan ---\n" + shell("/usr/sbin/sysctl", ["kern.ecfan"]) + "\n"
        report += "--- machdep ---\n" + shell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]) + "\n"
        report += "--- ec dump 0 ---\n" + shell("/usr/sbin/sysctl", ["-n", "kern.ecdump0"]) + "\n"
        report += "--- ec dump 1 ---\n" + shell("/usr/sbin/sysctl", ["-n", "kern.ecdump1"]) + "\n"
        report += "--- kexts ---\n" + shell("/usr/bin/kmutil", ["showloaded"]) + "\n"
        report += "--- logs ---\n" + ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "(no log)\n")
        let txt = NSHomeDirectory() + "/Desktop/\(name).txt"
        try? report.write(toFile: txt, atomically: true, encoding: .utf8)
        let zipPath = NSHomeDirectory() + "/Desktop/\(name).zip"
        run("/usr/bin/zip", ["-j", zipPath, txt])
        debugLog("exported diagnostics to \(zipPath)")
    }

    func shell(_ tool: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "(error)" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: d, encoding: .utf8) ?? ""
    }

    // MARK: 刷新

    func tick() {
        snapshot = sample()
        let s = snapshot
        cards["cpu"]?.valueLabel.stringValue = s.ok ? "\(s.cpu)°C" : "--"
        if s.gpu == 0 { snapshot.gpu = gpuTempFromEC() }
        let gpuTemp = snapshot.gpu
        cards["gpu"]?.valueLabel.stringValue = gpuTemp > 0 ? "\(gpuTemp)°C" : "不可用"
        cards["fan1"]?.valueLabel.stringValue = "\(s.fan1)"
        cards["fan2"]?.valueLabel.stringValue = "\(s.fan2)"
        cards["mem"]?.valueLabel.stringValue = String(format: "%.1f/%.0fG", s.memUsedGB, s.memTotalGB)
        cards["vram"]?.valueLabel.stringValue = String(format: "%.0f/%.0fM", s.vramUsedMB, s.vramTotalMB)
        cards["load"]?.valueLabel.stringValue = String(format: "%.2f", s.load1)
        cards["power"]?.valueLabel.stringValue = s.onAC ? "AC" : (s.batteryPct >= 0 ? "\(s.batteryPct)%" : "电池")
        cards["freq"]?.valueLabel.stringValue = s.cpuMHz > 0 ? String(format: "%.0f MHz", s.cpuMHz) : "--"
        cards["cpuw"]?.valueLabel.stringValue = s.cpuW > 0 ? String(format: "%.1f W", s.cpuW) : "--"
        cards["gpuw"]?.valueLabel.stringValue = "不可用"

        cpuHist.append(Double(s.cpu)); if cpuHist.count > 90 { cpuHist.removeFirst() }
        gpuHist.append(Double(gpuTemp)); if gpuHist.count > 90 { gpuHist.removeFirst() }
        fanHist.append(Double((s.fan1 + s.fan2) / 2)); if fanHist.count > 90 { fanHist.removeFirst() }
        chartCPU.series = cpuHist; chartCPU.needsDisplay = true
        chartGPU.series = gpuHist; chartGPU.needsDisplay = true
        chartFan.series = fanHist; chartFan.needsDisplay = true

        let (en, val) = eppStatus()
        perfState.stringValue = "EPP：" + (en == 1 ? "启用（值 \(val)）" : "关闭")
        fanState.stringValue = "当前：\(s.fan1) / \(s.fan2) RPM，CPU \(s.cpu)°C"

        if UserDefaults.standard.bool(forKey: "debugMode"), Int(Date().timeIntervalSince1970) % 10 == 0 {
            debugLog("tick fan=\(s.fan1)/\(s.fan2) cpu=\(s.cpu) gpu=\(s.gpu) mem=\(String(format: "%.1f", s.memUsedGB)) load=\(String(format: "%.2f", s.load1))")
        }

        if curveToggle.state == .on, s.ok {
            var pct = curveValue(for: s.cpu)
            if s.cpu >= 95 { pct = 100 }
            if abs(pct - lastApplied) >= 3 { lastApplied = pct; _ = setFan("\(pct)") }
        }
        updateStatusBar(s)

        if batteryToggle.state == .on, !s.onAC {
            _ = applyEPPPreset(5); _ = setCPBDisabled(true)
        }
    }

    // MARK: 主题应用

    func applyAppearance() {
        switch appearanceMode {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        default: window.appearance = nil
        }
        sidebar.appearance = window.appearance
        content.appearance = window.appearance
        applyTheme()
        for c in cards.values { c.apply(theme); c.needsDisplay = true }
        for c in [chartCPU, chartGPU, chartFan] { c?.needsDisplay = true }
        curveView.needsDisplay = true
        refresh(window.contentView)
        window.displayIfNeeded()
    }

    func applyTheme() {
        window.backgroundColor = .windowBackgroundColor
        for c in cards.values { c.apply(theme) }
        for c in [chartCPU, chartGPU, chartFan] { c?.theme = theme; c?.needsDisplay = true }
        curveView.theme = theme; curveView.needsDisplay = true
        paint(view: sidebar)
        paint(view: content)
    }

    func refresh(_ view: NSView?) {
        guard let v = view else { return }
        v.needsDisplay = true
        for sub in v.subviews { refresh(sub) }
    }

    func paint(view: NSView) {
        for sub in view.subviews {
            if let tf = sub as? NSTextField {
                tf.textColor = (tf.font?.pointSize ?? 12) <= 11 ? theme.sub : theme.text
            }
            paint(view: sub)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
