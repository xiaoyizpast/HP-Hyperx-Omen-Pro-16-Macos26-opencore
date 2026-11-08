import Cocoa

// 优先用 root 拥有的副本，其次用户目录下的工具
let SUDO_CLI = "/usr/local/bin/mtkwifi"
let CLI: String = {
    let candidates = [SUDO_CLI, NSHomeDirectory() + "/bin/mtkwifi", "/usr/local/bin/mtkwifi"]
    for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
    return SUDO_CLI
}()

struct StatusJSON: Decodable {
    let state: String
    let ssid: String?
    let rssi: Int?
    let channel: Int?
}

struct NetJSON: Decodable {
    let ssid: String
    let channel: Int
    let rssi: Int
    let security: String
    let joinable: Bool
    let current: Bool
}

// MARK: - process helpers

func run(_ tool: String, _ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func appleQuote(_ s: String) -> String {
    var r = "\""
    for c in s {
        if c == "\\" { r += "\\\\" }
        else if c == "\"" { r += "\\\"" }
        else if c == "\n" { r += "\\n" }
        else { r.append(c) }
    }
    return r + "\""
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

@discardableResult
func elevated(_ shell: String) -> (Int32, String) {
    run("/usr/bin/osascript", ["-e", "do shell script \(appleQuote(shell)) with administrator privileges"])
}

/// 免密白名单命令（scan / join / disconnect），不需要授权框
@discardableResult
func privileged(_ args: [String]) -> (Int32, String) {
    return run("/usr/bin/sudo", ["-n", SUDO_CLI] + args)
}

func tmpPath(_ prefix: String) -> String {
    let name = "\(prefix)-\(UUID().uuidString).tmp"
    return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
}

func logLine(_ s: String) {
    let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/WiFiMenu.log")
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(s)\n"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        h.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - app

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var busy = false
    var scanning = false
    var status: StatusJSON?
    var nets: [NetJSON] = []
    var lastScan = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mtk.wifimenu")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Wi-Fi")
        statusItem.button?.image?.isTemplate = true

        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refreshStatus()
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    // MARK: data

    func refreshStatus() {
        DispatchQueue.global().async {
            let (code, out) = run(CLI, ["status", "--json"])
            var s: StatusJSON?
            if code == 0, let d = out.data(using: .utf8) {
                s = try? JSONDecoder().decode(StatusJSON.self, from: d)
            }
            DispatchQueue.main.async {
                self.status = s
                let connected = (s?.state == "connected")
                self.statusItem.button?.image = NSImage(
                    systemSymbolName: connected ? "wifi" : "wifi.slash",
                    accessibilityDescription: "Wi-Fi")
                self.statusItem.button?.image?.isTemplate = true
                if self.menu.numberOfItems > 0 { self.rebuildMenu() }
            }
        }
    }

    func loadCachedNets() {
        let (code, out) = run(CLI, ["list", "--json"])
        guard code == 0, let d = out.data(using: .utf8),
              let list = try? JSONDecoder().decode([NetJSON].self, from: d) else { return }
        var seen = Set<String>()
        var result: [NetJSON] = []
        for n in list.sorted(by: { $0.rssi > $1.rssi }) {
            if seen.contains(n.ssid) { continue }
            seen.insert(n.ssid)
            result.append(n)
            if result.count >= 15 { break }
        }
        nets = result
    }

    /// 实时扫描：免密 sudo 白名单，只允许 scan --wait
    func triggerScan(completion: (() -> Void)? = nil) {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global().async {
            let (code, sout) = run("/usr/bin/sudo", ["-n", SUDO_CLI, "scan", "--wait"])
            if code != 0 { logLine("scan failed code=\(code) out=\(sout.suffix(200))") }
            if code == 0 {
                self.loadCachedNets()
                self.lastScan = Date()
            }
            DispatchQueue.main.async {
                self.scanning = false
                self.rebuildMenu()
                completion?()
            }
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        loadCachedNets()
        rebuildMenu()
        // 展开时实时扫描一次（最多 6 秒一次，避免频繁触发）
        if Date().timeIntervalSince(lastScan) > 6 {
            triggerScan()
        }
    }

    func rebuildMenu() {
        guard let menu = menu else { return }
        menu.removeAllItems()

        let st = status
        var title: String
        if let s = st, s.state == "connected", let ssid = s.ssid {
            title = "已连接：\(ssid)   \(s.rssi ?? 0) dBm   ch\(s.channel ?? 0)"
        } else if scanning {
            title = "正在扫描…"
        } else {
            title = "未连接"
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if scanning {
            let it = NSMenuItem(title: "   扫描中…", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }

        menu.addItem(.separator())

        if nets.isEmpty {
            let it = NSMenuItem(title: "（没有可用网络）", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        } else {
            for n in nets {
                let mark = n.current ? "✓ " : "   "
                let locked = n.joinable ? "" : " 🔒"
                let item = NSMenuItem(title: "\(mark)\(n.ssid)\(locked)   \(n.rssi) dBm  ch\(n.channel)",
                                      action: #selector(joinClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [n.ssid, n.joinable, n.security]
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        addItem(menu, "刷新", #selector(refreshClicked))
        addItem(menu, "重新扫描", #selector(rescanClicked))
        addItem(menu, "打开登录页（校园网）", #selector(portalClicked))
        addItem(menu, "断开连接", #selector(disconnectClicked))
        menu.addItem(.separator())
        addItem(menu, "退出", #selector(NSApplication.terminate(_:)))
    }

    func addItem(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        menu.addItem(it)
    }

    // MARK: actions

    @objc func refreshClicked() {
        refreshStatus()
        loadCachedNets()
        rebuildMenu()
    }

    @objc func rescanClicked() {
        triggerScan()
    }

    @objc func disconnectClicked() {
        guard !busy else { return }
        busy = true
        DispatchQueue.global().async {
            let (code, _) = privileged(["disconnect"])
            if code != 0 {
                _ = elevated("\(shellQuote(CLI)) disconnect")
            }
            self.busy = false
            DispatchQueue.main.async {
                self.refreshStatus()
                self.triggerScan()
            }
        }
    }

    /// 打开校园网/门户登录页：跟随重定向拿到真实门户地址，再交给浏览器
    @objc func portalClicked() {
        openPortal()
    }

    func openPortal() {
        DispatchQueue.global().async {
            for attempt in 0..<4 {
                let (_, url) = run("/usr/bin/curl", ["-s", "-L", "-m", "6", "-o", "/dev/null",
                                                     "-w", "%{url_effective}",
                                                     "http://captive.apple.com/hotspot-detect.html"])
                let effective = url.trimmingCharacters(in: .whitespacesAndNewlines)
                let hijacked = !effective.isEmpty && !effective.contains("captive.apple.com")
                if hijacked {
                    DispatchQueue.main.async {
                        // 门户依赖 WebRTC 取内网 IPv4，Chrome/Edge/Safari 会把它
                        // mDNS 化后被门户丢弃，故固定走 campus-portal profile 的 Firefox。
                        let ffApp = NSHomeDirectory() + "/Applications/Firefox.app"
                        if FileManager.default.fileExists(atPath: ffApp) {
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                            p.arguments = ["-na", ffApp, "--args",
                                           "-P", "campus-portal", "-new-instance", effective]
                            try? p.run()
                        } else {
                            NSWorkspace.shared.open(URL(string: effective) ?? URL(string: "http://captive.apple.com")!)
                        }
                    }
                    return
                }
                if attempt < 3 { Thread.sleep(forTimeInterval: 2.0) }
            }
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "没有检测到登录门户"
                a.informativeText = "当前网络看起来可以直接上网。若仍需要认证，请手动打开学校的门户地址。"
                a.runModal()
            }
        }
    }

    @objc func joinClicked(_ sender: NSMenuItem) {
        guard let args = sender.representedObject as? [Any],
              let ssid = args[0] as? String else { return }
        let security = args[2] as? String ?? ""
        guard !busy else { return }

        if security.contains("open") {
            join(ssid: ssid, password: nil, open: true)
            return
        }

        // 先试免密（已保存的网络）。未保存时工具会立即返回 "is not saved"，不会动网卡。
        busy = true
        DispatchQueue.global().async {
            let (code, out) = privileged(["join", ssid])
            logLine("try-join ssid=\(ssid) code=\(code) out=\(out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(200))")
            DispatchQueue.main.async {
                self.busy = false
                if code == 0 {
                    self.refreshStatus()
                    self.triggerScan()
                } else if out.contains("is not saved") {
                    self.askPassword(for: ssid)
                } else {
                    self.refreshStatus()
                    self.triggerScan()
                    let a = NSAlert()
                    a.messageText = "连接失败"
                    a.informativeText = String(out.suffix(400))
                    a.alertStyle = .warning
                    a.runModal()
                }
            }
        }
    }

    func askPassword(for ssid: String) {
        let alert = NSAlert()
        alert.messageText = "连接到 \(ssid)"
        alert.informativeText = "这个网络还没有保存密码，请输入 Wi-Fi 密码（WPA2-PSK）"
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "密码"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() != .alertFirstButtonReturn { return }
        let pw = field.stringValue
        if pw.count < 8 { NSSound.beep(); return }
        join(ssid: ssid, password: pw, open: false)
    }

    func join(ssid: String, password: String?, open: Bool) {
        busy = true
        DispatchQueue.global().async {
            var code: Int32 = -1
            var out = ""
            var cleanup: [String] = []

            if let pw = password {
                // 需要密码：写一次性文件 + expect 交互，走授权框（root）
                let pwFile = tmpPath("mtkpw")
                let expFile = tmpPath("mtkexp")
                try? pw.write(toFile: pwFile, atomically: true, encoding: .utf8)
                chmod(pwFile, 0o600)
                let script = """
                set timeout 45
                set fh [open "\(pwFile)" r]
                set pw [string trim [read $fh]]
                close $fh
                spawn \(CLI) join "\(ssid)" --ask
                expect {
                  -re "passphrase:" { send -- "$pw\\r"; exp_continue }
                  -re "again:" { send -- "$pw\\r"; exp_continue }
                  eof { }
                  timeout { exit 3 }
                }
                """
                try? script.write(toFile: expFile, atomically: true, encoding: .utf8)
                chmod(expFile, 0o700)
                cleanup = [pwFile, expFile]
                (code, out) = elevated("/usr/bin/expect \(shellQuote(expFile))")
            } else {
                // 开放网络 / 已保存网络：免密白名单，不弹授权框
                var args = ["join", ssid]
                if open { args.append("--open") }
                (code, out) = privileged(args)
                if code != 0 && !out.contains("not saved") {
                    // 白名单不可用时回退到授权框
                    let shell = "\(shellQuote(CLI)) " + args.map { shellQuote($0) }.joined(separator: " ")
                    (code, out) = elevated(shell)
                }
            }
            for f in cleanup { try? FileManager.default.removeItem(atPath: f) }
            logLine("join ssid=\(ssid) open=\(open) pw=\(password != nil) code=\(code) out=\(out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))")

            DispatchQueue.main.async {
                self.busy = false
                self.refreshStatus()
                self.triggerScan()
                if code != 0 {
                    let a = NSAlert()
                    a.messageText = "连接失败"
                    a.informativeText = String(out.suffix(400))
                    a.alertStyle = .warning
                    a.runModal()
                } else if open {
                    // 开放网络：连上后自动拉起门户登录页（自带重试）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.openPortal()
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
