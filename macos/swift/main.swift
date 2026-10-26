import Cocoa

// Mini GUI : miroir en direct, enregistrement et photo des écrans du téléphone (scrcpy + adb embarqués).
// Textes dans Strings.swift (généré depuis back-screen-i18n/strings.py).

let resources = Bundle.main.resourcePath ?? "."
let scrcpyPath = resources + "/scrcpy"
let adbPath = resources + "/adb"
let outDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/EcranArriere")

/// Serveur adb PRIVÉ de l'app : un autre outil Android (Android Studio, Vysor, un autre scrcpy…) ne peut ni le couper
/// (versions d'adb différentes) ni nous voler le téléphone, et nous ne touchons jamais à son serveur (port 5037).
let adbPort = "5137"

func scrcpyEnv() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["ADB"] = adbPath
    env["ANDROID_ADB_SERVER_PORT"] = adbPort
    env["SCRCPY_SERVER_PATH"] = resources + "/scrcpy-server"
    return env
}

/// Lance un outil et attend la fin. `mergeErr` : mélange stderr dans la sortie (texte), sinon stdout seul (binaire).
@discardableResult
func run(_ exe: String, _ args: [String], mergeErr: Bool = true) -> (data: Data, text: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.environment = scrcpyEnv()
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = mergeErr ? pipe : FileHandle.nullDevice
    do { try p.run() } catch { return (Data(), "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (data, String(data: data, encoding: .utf8) ?? "")
}

/// Un AUTRE serveur adb (port standard 5037) tient-il un téléphone prêt ? Lecture seule par le protocole brut :
/// aucune négociation de version, donc rien ne peut être coupé chez l'autre outil.
func phoneHeldByOtherAdb() -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = UInt16(5037).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard ok == 0 else { return false }
    let req = Array("000chost:devices".utf8)
    guard send(fd, req, req.count, 0) == req.count else { return false }
    var buf = [UInt8](repeating: 0, count: 4096)
    var got = Data()
    while true {
        let n = recv(fd, &buf, buf.count, 0)
        if n <= 0 { break }
        got.append(contentsOf: buf[0..<n])
        if got.count > 8192 { break }
    }
    let text = String(data: got, encoding: .utf8) ?? ""
    return text.hasPrefix("OKAY") && text.split(separator: "\n").contains { $0.hasSuffix("\tdevice") }
}

func spawn(_ args: [String]) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: scrcpyPath)
    p.arguments = args
    p.environment = scrcpyEnv()
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    return p
}

/// Arrêt propre (SIGINT) pour que le .mp4 soit finalisé.
func stop(_ p: Process?) {
    guard let p = p, p.isRunning else { return }
    p.interrupt()
    for _ in 0..<50 where p.isRunning { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning { p.terminate() }
}

func running(_ ps: [Process]) -> Bool { ps.contains { $0.isRunning } }

func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
        (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }
}

// MARK: modèle

struct Phone {
    let serial: String
    let state: String   // device / unauthorized / offline…
    let model: String
    var name = ""   // nom commercial (ro.product.marketname)
    var isWifi: Bool { serial.contains(":") }
    var title: String {
        let label = !name.isEmpty ? name : (model.isEmpty ? serial : model)
        var s = "\(label) (\(isWifi ? "Wi-Fi" : "USB"))"
        if state != "device" { s += " – \(state == "unauthorized" ? t("phone.unauthorized") : state)" }
        return s
    }
}

func parseDevices(_ text: String) -> [Phone] {
    var out: [Phone] = []
    for line in text.split(separator: "\n") {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2, !line.hasPrefix("*"), !line.hasPrefix("List of") else { continue }
        let model = parts.first(where: { $0.hasPrefix("model:") })?.dropFirst(6) ?? ""
        out.append(Phone(serial: parts[0], state: parts[1], model: String(model)))
    }
    return out
}

/// Nom commercial lu dans le téléphone (ex. « Xiaomi 18 Pro Max »), vide si introuvable.
func marketName(_ serial: String) -> String {
    for prop in ["ro.product.marketname", "ro.product.odm.marketname", "ro.product.vendor.marketname"] {
        let s = run(adbPath, ["-s", serial, "shell", "getprop", prop]).text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty, !s.contains("error:") { return s }
    }
    return ""
}

enum Role { case front, rear, main, other }

struct DisplayInfo {
    let id: String          // id Android (--display-id)
    let size: String
    let localId: String?    // id physique pour screencap -d
    var role: Role
    var name: String {
        switch role {
        case .front: return t("display.front")
        case .rear: return t("display.rear")
        case .main: return t("display.main")
        case .other: return t("display.other", id)
        }
    }
    /// partie ASCII du nom de fichier
    var slug: String {
        switch role {
        case .front: return "avant"
        case .rear: return "arriere"
        case .main: return "principal"
        case .other: return "ecran\(id)"
        }
    }
}

/// Écrans physiques du téléphone, nommés (avant / arrière / principal). Les écrans virtuels sont ignorés.
func loadDisplays(_ serial: String) -> [DisplayInfo] {
    let listing = run(scrcpyPath, ["-s", serial, "--list-displays"]).text
    let raw = matches("--display-id=(\\d+)\\s+\\(([^)]*)\\)", in: listing)
    if raw.isEmpty { return [] }
    let dump = run(adbPath, ["-s", serial, "shell", "dumpsys", "display"]).text
    var local: [String: String] = [:]
    for m in matches("displayId (\\d+),.*?uniqueId \"([^\"]*)\"", in: dump) where m[1].hasPrefix("local:") {
        local[m[0]] = String(m[1].dropFirst(6))
    }
    let known = !local.isEmpty
    let physical = raw.filter { !known || $0[0] == "0" || local[$0[0]] != nil }
    var rearTaken = false
    return physical.map { m in
        var role = Role.other
        if m[0] == "0" { role = physical.count > 1 ? .front : .main }
        else if !rearTaken { role = .rear; rearTaken = true }
        return DisplayInfo(id: m[0], size: m[1], localId: local[m[0]], role: role)
    }
}

// MARK: HD ×2 (expérimental) — double la définition de l'écran arrière côté téléphone (wm size / wm density)

struct DisplayMode {
    let w: Int, h: Int, dpi: Int           // valeurs physiques
    let ovW: Int?, ovH: Int?, ovDpi: Int?  // réglages forcés éventuels
    var isDoubled: Bool { ovW == 2 * w && ovH == 2 * h && ovDpi == 2 * dpi }   // signature exacte du HD ×2
    var hasOverride: Bool { ovW != nil || ovH != nil || ovDpi != nil }
}

func readDisplayMode(_ serial: String, _ id: String) -> DisplayMode? {
    let size = run(adbPath, ["-s", serial, "shell", "wm", "size", "-d", id]).text
    let dens = run(adbPath, ["-s", serial, "shell", "wm", "density", "-d", id]).text
    guard let ps = matches("Physical size:\\s*(\\d+)x(\\d+)", in: size).first,
          let pd = matches("Physical density:\\s*(\\d+)", in: dens).first,
          let w = Int(ps[0]), let h = Int(ps[1]), let dpi = Int(pd[0]) else { return nil }
    let os = matches("Override size:\\s*(\\d+)x(\\d+)", in: size).first
    let od = matches("Override density:\\s*(\\d+)", in: dens).first
    return DisplayMode(w: w, h: h, dpi: dpi, ovW: os.flatMap { Int($0[0]) }, ovH: os.flatMap { Int($0[1]) }, ovDpi: od.flatMap { Int($0[0]) })
}

/// Services Xiaomi de l'écran arrière (ex. com.xiaomi.subscreencenter). On ne relance QUE ceux-là, jamais SystemUI ni une app au hasard.
func rearServicePackages(_ serial: String) -> [String] {
    run(adbPath, ["-s", serial, "shell", "pm", "list", "packages"]).text
        .split(separator: "\n")
        .map { $0.replacingOccurrences(of: "package:", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.range(of: "subscreen|backscreen|rearscreen", options: [.regularExpression, .caseInsensitive]) != nil }
}

/// Sans ce redémarrage, le widget de l'écran arrière reste figé à l'ancienne taille (cache de mise en page).
func restartRearService(_ serial: String) {
    for pkg in rearServicePackages(serial) { run(adbPath, ["-s", serial, "shell", "am", "force-stop", pkg]) }
}

enum UpscaleResult { case ok, needsSecurity, custom, failed(String) }

func enableUpscale(_ serial: String, _ d: DisplayInfo) -> UpscaleResult {
    guard let m = readDisplayMode(serial, d.id) else { return .failed("wm size") }
    if m.isDoubled { return .ok }
    if m.hasOverride { return .custom }          // réglage perso de l'utilisateur : on n'y touche pas
    func denied(_ t: String) -> Bool { t.contains("SecurityException") || t.contains("WRITE_SECURE_SETTINGS") }
    func clean(_ t: String) -> String { String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)) }
    let r1 = run(adbPath, ["-s", serial, "shell", "wm", "size", "\(2 * m.w)x\(2 * m.h)", "-d", d.id]).text
    if denied(r1) { return .needsSecurity }
    if r1.contains("Exception") { return .failed(clean(r1)) }
    let r2 = run(adbPath, ["-s", serial, "shell", "wm", "density", "\(2 * m.dpi)", "-d", d.id]).text
    if denied(r2) || r2.contains("Exception") {
        run(adbPath, ["-s", serial, "shell", "wm", "size", "reset", "-d", d.id])
        return denied(r2) ? .needsSecurity : .failed(clean(r2))
    }
    restartRearService(serial)
    Thread.sleep(forTimeInterval: 2.5)
    return .ok
}

func resetUpscale(_ serial: String, _ id: String) {
    run(adbPath, ["-s", serial, "shell", "wm", "size", "reset", "-d", id])
    run(adbPath, ["-s", serial, "shell", "wm", "density", "reset", "-d", id])
    restartRearService(serial)
}

enum Quality: Int, CaseIterable {
    case light, normal, max
    var title: String {
        switch self {
        case .light: return t("quality.light")
        case .normal: return t("quality.normal")
        case .max: return t("quality.max")
        }
    }
    /// Débit (bit/s) et images/s ; en HD ×2 l'image a 4× plus de pixels, on monte donc le débit.
    func numbers(upscaled: Bool = false) -> (bitrate: Int, fps: Int) {
        switch self {
        case .light: return (upscaled ? 8_000_000 : 4_000_000, 30)
        case .normal: return (upscaled ? 16_000_000 : 8_000_000, 60)
        case .max: return (upscaled ? 24_000_000 : 20_000_000, 120)
        }
    }
    func args(upscaled: Bool = false) -> [String] {
        let n = numbers(upscaled: upscaled)
        return ["--video-bit-rate=\(n.bitrate / 1_000_000)M", "--max-fps=\(n.fps)"]
    }
}

// MARK: application

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var status = NSTextField(wrappingLabelWithString: "")
    var devicePopup = NSPopUpButton()
    var displayPopup = NSPopUpButton()
    var qualityPopup = NSPopUpButton()
    var langPopup = NSPopUpButton()
    var mirrorBtn = NSButton()
    var recBtn = NSButton()
    var photoBtn = NSButton()
    var viewCheck = NSButton()
    var timerLabel = NSTextField(labelWithString: " ")

    var devices: [Phone] = []
    var displays: [DisplayInfo] = []
    var targets: [[DisplayInfo]] = []   // une entrée par ligne du menu « Écran »
    var displaysSerial: String?
    var pendingSelect: String?
    var mirrors: [Process] = []
    var records: [Process] = []
    var recStart = Date()
    var recFiles: [URL] = []
    var refreshing = false
    var phoneNames: [String: String] = [:]
    var showWhileRecording = true
    var launchGen = 0   // annule les lancements en attente quand on arrête
    var launchPending = 0   // lancements programmés, pas encore exécutés
    var upscaleCheck = NSButton()
    var upscaleWanted = false
    var upscaleSession: (serial: String, displayId: String)?   // HD ×2 appliqué (ou en cours) par l'app
    var upscaleBusy = false
    var photoBusy = false
    var activity: NSObjectProtocol?
    var frames: [PhoneFrame] = []
    var framePopup = NSPopUpButton()
    var frameId = UserDefaults.standard.string(forKey: "frameId") ?? Frames.noneId      // « Aucun cadre » par défaut
    var frameWanted: Bool { frameId != Frames.noneId && currentFrame != nil }
    var lives: [LiveMirror] = []
    var pendingFramed: [(src: URL, name: String)] = []
    var framedBusy = false
    var currentFrame: PhoneFrame? { frames.first(where: { $0.id == frameId }) }
    var liveRunning: Bool { lives.contains { $0.isRunning } }
    func usesLive(_ d: DisplayInfo) -> Bool { frameWanted && currentFrame != nil && d.role == .rear }

    var selectedPhone: Phone? {
        let i = devicePopup.indexOfSelectedItem
        return devices.indices.contains(i) ? devices[i] : nil
    }
    var selectedTargets: [DisplayInfo] {
        let i = displayPopup.indexOfSelectedItem
        return targets.indices.contains(i) ? targets[i] : [DisplayInfo(id: "1", size: "", localId: nil, role: .rear)]
    }
    var quality: Quality { Quality(rawValue: qualityPopup.indexOfSelectedItem) ?? .normal }

    func applicationDidFinishLaunching(_ n: Notification) {
        // Empêche App Nap de ralentir les minuteries quand l'app est derrière la fenêtre de miroir (remise à zéro du HD ×2, détection, chrono)
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Rear Screen: miroir / enregistrement")
        buildMenu()
        buildWindow()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let sub = NSMenu()
        sub.addItem(withTitle: t("menu.quit", t("app.name")), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = sub
        NSApp.mainMenu = main
    }

    func labeled(_ text: String, _ control: NSView, extra: NSView? = nil) -> NSStackView {
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        l.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let row = NSStackView(views: [l, control] + (extra.map { [$0] } ?? []))
        row.spacing = 8
        return row
    }

    /// Bouton « Liquid Glass » (macOS 26+), bouton arrondi classique avant.
    func styleButton(_ b: NSButton, tint: NSColor? = nil) {
        b.controlSize = .large
        if #available(macOS 26.0, *) {
            b.bezelStyle = .glass
            if let c = tint { b.bezelColor = c }
        } else {
            b.bezelStyle = .rounded
        }
    }

    /// Carte en verre (Liquid Glass sur macOS 26+, matériau translucide avant).
    func card(_ views: [NSView]) -> NSView {
        let inner = NSStackView(views: views)
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        for v in views where v is NSButton || v is NSStackView && (v as! NSStackView).distribution == .fillEqually || v === timerLabel {
            v.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -28).isActive = true
        }
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = 22
            g.contentView = inner
            return g
        }
        let v = NSVisualEffectView()
        v.material = .popover; v.blendingMode = .withinWindow; v.state = .active
        v.wantsLayer = true; v.layer?.cornerRadius = 18; v.layer?.masksToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: v.leadingAnchor), inner.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            inner.topAnchor.constraint(equalTo: v.topAnchor), inner.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }

    func buildWindow() {
        status = NSTextField(wrappingLabelWithString: t("status.searching"))
        devicePopup = NSPopUpButton()
        displayPopup = NSPopUpButton()
        qualityPopup = NSPopUpButton()
        langPopup = NSPopUpButton()
        mirrorBtn = NSButton(title: t("mirror.start"), target: self, action: #selector(toggleMirror))
        recBtn = NSButton(title: t("rec.start"), target: self, action: #selector(toggleRecord))
        photoBtn = NSButton(title: t("btn.photo"), target: self, action: #selector(takePhoto))
        viewCheck = NSButton(checkboxWithTitle: t("rec.viewCheck"), target: self, action: #selector(viewCheckChanged))
        timerLabel = NSTextField(labelWithString: " ")

        viewCheck.state = showWhileRecording ? .on : .off
        upscaleCheck = NSButton(checkboxWithTitle: t("upscale.check"), target: self, action: #selector(upscaleCheckChanged))
        upscaleCheck.state = upscaleWanted ? .on : .off
        upscaleCheck.toolTip = t("upscale.tip")
        upscaleCheck.isEnabled = displays.contains { $0.role == .rear }
        if frames.isEmpty { frames = Frames.loadAll() }
        framePopup = NSPopUpButton()
        fillFramePopup()
        framePopup.target = self; framePopup.action = #selector(frameChanged)
        framePopup.toolTip = t("frame.tip")
        timerLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        timerLabel.alignment = .center
        timerLabel.isHidden = true
        status.preferredMaxLayoutWidth = 320
        status.textColor = .labelColor
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

        devicePopup.target = self; devicePopup.action = #selector(deviceChanged)
        for q in Quality.allCases { qualityPopup.addItem(withTitle: q.title) }
        qualityPopup.selectItem(at: Quality.normal.rawValue)

        for l in Lang.allCases { langPopup.addItem(withTitle: l.native) }
        langPopup.selectItem(at: Lang.allCases.firstIndex(of: I18N.current) ?? 0)
        langPopup.target = self; langPopup.action = #selector(langChanged)
        langPopup.controlSize = .small
        langPopup.toolTip = t("lang.label")

        let refreshBtn = NSButton(title: "↻", target: self, action: #selector(forceRefresh))
        refreshBtn.toolTip = t("tip.refresh")
        styleButton(refreshBtn)

        let folder = NSButton(title: t("btn.folder"), target: self, action: #selector(openFolder))
        let wifi = NSButton(title: t("btn.wifi"), target: self, action: #selector(switchToWifi))
        wifi.toolTip = t("tip.wifi")
        let manual = NSButton(title: t("btn.manual"), target: self, action: #selector(manualConnect))
        styleButton(mirrorBtn, tint: .systemIndigo)
        styleButton(recBtn, tint: .systemRed)
        for b in [photoBtn, folder, wifi, manual] { styleButton(b) }

        let photoRow = NSStackView(views: [photoBtn, folder]); photoRow.distribution = .fillEqually; photoRow.spacing = 8
        let wifiRow = NSStackView(views: [wifi, manual]); wifiRow.distribution = .fillEqually; wifiRow.spacing = 8

        let title = NSTextField(labelWithString: t("app.name"))
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let titleRow = NSStackView(views: [title, langPopup])
        titleRow.distribution = .fill

        let cardA = card([status,
                          labeled(t("label.phone"), devicePopup, extra: refreshBtn),
                          labeled(t("label.display"), displayPopup),
                          labeled(t("label.quality"), qualityPopup),
                          labeled(t("frame.label"), framePopup)])
        let cardB = card([mirrorBtn, recBtn, viewCheck, upscaleCheck, timerLabel, photoRow])
        let cardC = card([wifiRow])

        for p in [devicePopup, displayPopup, qualityPopup, framePopup] {
            p.widthAnchor.constraint(equalToConstant: 224).isActive = true
        }

        let stack = NSStackView(views: [titleRow, cardA, cardB, cardC])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for c in [titleRow, cardA, cardB, cardC] { c.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

        // fond translucide sous les cartes
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 42),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            root.widthAnchor.constraint(equalToConstant: 400),
        ])

        let oldTopLeft = window.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        if let w = window { w.delegate = nil; w.orderOut(nil) }
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
        window.delegate = self
        if let p = oldTopLeft { window.setFrameTopLeftPoint(p) } else { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStatus(_ s: String) { DispatchQueue.main.async { self.status.stringValue = s } }

    @objc func viewCheckChanged() { showWhileRecording = viewCheck.state == .on }
    /// Menu « Cadre » : « Aucun cadre », puis les cadres disponibles, puis « Ouvrir le dossier des cadres… ».
    func fillFramePopup() {
        framePopup.removeAllItems()
        framePopup.addItem(withTitle: t("frame.none"))
        for f in frames { framePopup.addItem(withTitle: f.name) }
        framePopup.menu?.addItem(.separator())
        framePopup.addItem(withTitle: t("frame.openFolder"))
        selectCurrentFrame()
    }

    func selectCurrentFrame() {
        framePopup.selectItem(at: (frames.firstIndex(where: { $0.id == frameId }).map { $0 + 1 }) ?? 0)
    }

    @objc func frameChanged() {
        let i = framePopup.indexOfSelectedItem
        if i > frames.count {                                        // dernière ligne : ouvrir le dossier des cadres
            try? FileManager.default.createDirectory(at: Frames.userDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Frames.userDir)
            selectCurrentFrame()
            return
        }
        frameId = i == 0 ? Frames.noneId : frames[i - 1].id
        UserDefaults.standard.set(frameId, forKey: "frameId")
    }

    @objc func upscaleCheckChanged() {
        upscaleWanted = upscaleCheck.state == .on
        fillDisplays(keep: selectedTargets.map(\.id))   // la résolution affichée suit la case
    }

    /// Résolution affichée dans le menu « Écran » : doublée pour l'écran arrière quand HD ×2 est coché.
    func sizeLabel(_ d: DisplayInfo) -> String {
        guard upscaleWanted, d.role == .rear else { return d.size }
        let dims = d.size.split(separator: "x").compactMap { Int($0) }
        return dims.count == 2 ? "\(dims[0] * 2)x\(dims[1] * 2)" : d.size
    }

    @objc func langChanged() {
        guard let l = Lang.allCases[safe: langPopup.indexOfSelectedItem] else { return }
        let phone = selectedPhone?.serial
        let q = qualityPopup.indexOfSelectedItem
        let prev = selectedTargets.map(\.id)
        I18N.set(l)
        frames = Frames.loadAll()          // le nom du cadre par défaut est traduit
        buildMenu()
        buildWindow()
        qualityPopup.selectItem(at: q)
        fillDevices(select: phone)
        fillDisplays(keep: prev)
        updateStatus()
    }

    // MARK: détection du téléphone

    @objc func forceRefresh() { displaysSerial = nil; frames = Frames.loadAll(); fillFramePopup(); refresh() }
    @objc func deviceChanged() { displaysSerial = nil; refresh() }

    var phoneBusyElsewhere = false
    var noPhoneStreak = 0
    var lastServerRestart = Date.distantPast

    @objc func refresh() {
        if refreshing { return }
        refreshing = true
        let wanted = pendingSelect ?? selectedPhone?.serial
        let knownSerial = displaysSerial
        let knownDisplays = displays
        let knownNames = phoneNames
        let upActive = upscaleSession != nil || upscaleBusy
        let wasBusy = phoneBusyElsewhere
        let streak = noPhoneStreak
        let idle = !running(mirrors) && !running(records) && lives.isEmpty
        let canRestart = Date().timeIntervalSince(lastServerRestart) > 30
        DispatchQueue.global().async {
            var healed = false
            var list = parseDevices(run(adbPath, ["devices", "-l"]).text)
            var busy = !list.contains { $0.state == "device" } && phoneHeldByOtherAdb()
            // Notre serveur ne voit plus le téléphone alors qu'il n'est pas pris ailleurs : l'autre outil vient de le libérer, ou le câble a été
            // débranché/rebranché sans quitter l'app → après quelques tours à vide, on relance notre serveur (jamais pendant un miroir/enregistrement)
            var restarted = false
            if !list.contains(where: { $0.state == "device" }) && !busy && ((wasBusy) || (streak >= 3 && idle && canRestart)) {
                restarted = true
                run(adbPath, ["kill-server"])
                list = parseDevices(run(adbPath, ["devices", "-l"]).text)
                busy = false
            }
            var names = knownNames
            for i in list.indices where list[i].state == "device" {
                let serial = list[i].serial
                if names[serial] == nil { names[serial] = marketName(serial) }
                list[i].name = names[serial] ?? ""
            }
            let chosen = list.first(where: { $0.serial == wanted })
                ?? list.first(where: { $0.state == "device" }) ?? list.first
            var found = knownDisplays
            var serial = knownSerial
            if let c = chosen, c.state == "device", c.serial != knownSerial || knownDisplays.isEmpty {
                found = loadDisplays(c.serial)
                serial = found.isEmpty ? nil : c.serial
                // Un HD ×2 laissé actif (câble débranché, plantage) est remis à la normale — seulement s'il porte notre signature exacte
                if !upActive, let rear = found.first(where: { $0.role == .rear }),
                   let m = readDisplayMode(c.serial, rear.id), m.isDoubled {
                    resetUpscale(c.serial, rear.id); healed = true
                    found = loadDisplays(c.serial)   // tailles relues après la remise à la normale
                }
            } else if chosen?.state != "device" {
                found = []; serial = nil
            }
            DispatchQueue.main.async {
                self.refreshing = false
                self.phoneBusyElsewhere = busy
                if restarted { self.lastServerRestart = Date() }
                self.noPhoneStreak = (list.contains { $0.state == "device" } || busy) ? 0 : self.noPhoneStreak + 1
                self.phoneNames = names
                self.apply(list, chosen: chosen, displays: found, serial: serial)
                if healed { self.status.stringValue = t("upscale.healed") }
            }
        }
    }

    func apply(_ list: [Phone], chosen: Phone?, displays found: [DisplayInfo], serial: String?) {
        let phoneChanged = list.map(\.title) != devices.map(\.title) || list.map(\.serial) != devices.map(\.serial)
        devices = list
        if phoneChanged || devicePopup.numberOfItems == 0 { fillDevices(select: chosen?.serial) }
        else if let c = chosen, let i = devices.firstIndex(where: { $0.serial == c.serial }) { devicePopup.selectItem(at: i) }
        if chosen?.serial == pendingSelect { pendingSelect = nil }

        displaysSerial = serial
        let displaysChanged = found.map(\.id) != displays.map(\.id) || displayPopup.numberOfItems == 0
        displays = found
        upscaleCheck.isEnabled = found.contains { $0.role == .rear }
        if displaysChanged { fillDisplays(keep: nil) }
        updateStatus()
    }

    func fillDevices(select serial: String?) {
        devicePopup.removeAllItems()
        for p in devices { devicePopup.addItem(withTitle: p.title) }
        if let s = serial, let i = devices.firstIndex(where: { $0.serial == s }) { devicePopup.selectItem(at: i) }
    }

    /// Remplit le menu « Écran » : chaque écran nommé, + « Les deux écrans » s'il y en a au moins deux.
    func fillDisplays(keep previous: [String]?) {
        displayPopup.removeAllItems()
        targets = []
        if displays.isEmpty {
            let d = DisplayInfo(id: "1", size: "", localId: nil, role: .rear)
            targets = [[d]]
            displayPopup.addItem(withTitle: d.name)
            return
        }
        for d in displays {
            targets.append([d])
            displayPopup.addItem(withTitle: "\(d.name) (\(sizeLabel(d)))")
        }
        if displays.count >= 2 {
            targets.append(displays)
            displayPopup.addItem(withTitle: t("display.both"))
        }
        // sélection : celle d'avant (changement de langue), sinon l'écran arrière
        if let prev = previous, let i = targets.firstIndex(where: { $0.map(\.id) == prev }) {
            displayPopup.selectItem(at: i)
        } else if let i = targets.firstIndex(where: { $0.count == 1 && $0[0].role == .rear }) {
            displayPopup.selectItem(at: i)
        }
    }

    func updateStatus() {
        guard let c = selectedPhone else { status.stringValue = t(phoneBusyElsewhere ? "status.busy" : "status.noPhone"); return }
        switch c.state {
        case "device":
            status.stringValue = displays.isEmpty ? t("status.noDisplays") : t("status.connected")
        case "unauthorized": status.stringValue = t("status.unauthorized")
        case "offline": status.stringValue = t("status.offline")
        default: status.stringValue = t("status.state", c.state)
        }
    }

    // MARK: miroir / enregistrement

    func readyPhone() -> Phone? {
        guard let p = selectedPhone, p.state == "device" else {
            let a = NSAlert()
            a.messageText = t("alert.noPhone")
            a.informativeText = status.stringValue
            a.runModal()
            return nil
        }
        return p
    }

    /// Fenêtres côte à côte quand on montre plusieurs écrans : taille réduite + position, sans toucher à la qualité vidéo.
    func windowLayout(_ ts: [DisplayInfo]) -> [(x: Int, w: Int, h: Int)?] {
        if ts.count < 2 { return ts.map { _ in nil } }
        var x = 20
        return ts.map { d in
            let dims = d.size.split(separator: "x").compactMap { Double($0) }
            let (W, H) = dims.count == 2 ? (dims[0], dims[1]) : (976.0, 596.0)
            let k = min(1, 560 / W, 720 / H)
            let slot = (x: x, w: Int(W * k), h: Int(H * k))
            x += slot.w + 24
            return slot
        }
    }

    func args(_ p: Phone, _ d: DisplayInfo, slot: (x: Int, w: Int, h: Int)?, upscaled: Bool = false) -> [String] {
        var a = ["-s", p.serial, "--display-id=\(d.id)", "--no-audio", "--window-title=\(d.name)"] + quality.args(upscaled: upscaled)
        if let s = slot {
            a += ["--window-x=\(s.x)", "--window-y=60", "--window-width=\(s.w)", "--window-height=\(s.h)"]
        } else if upscaled {
            // fenêtre à la taille physique : sur écran Retina, c'est exactement 1 pixel vidéo = 1 pixel écran
            let dims = d.size.split(separator: "x").compactMap { Int($0) }
            if dims.count == 2 { a += ["--window-width=\(dims[0])", "--window-height=\(dims[1])"] }
        }
        return a
    }

    /// Applique le HD ×2 à l'écran arrière si la case est cochée, puis appelle `then` avec les écrans concernés.
    func prepareUpscale(_ p: Phone, _ ts: [DisplayInfo], then: @escaping (Set<String>) -> Void) {
        guard upscaleCheck.state == .on, let rear = ts.first(where: { $0.role == .rear }) else { then([]); return }
        // pas de changement de résolution sous un flux déjà en cours
        if upscaleSession == nil && (running(mirrors) || running(records)) { then([]); return }
        upscaleBusy = true
        status.stringValue = t("upscale.enabling")
        DispatchQueue.global().async {
            let r = enableUpscale(p.serial, rear)
            DispatchQueue.main.async {
                self.upscaleBusy = false
                switch r {
                case .ok:
                    self.upscaleSession = (p.serial, rear.id)
                    then([rear.id])
                case .needsSecurity:
                    let a = NSAlert()
                    a.messageText = t("upscale.needSecurity.title")
                    a.informativeText = t("upscale.needSecurity.info")
                    a.runModal()
                    then([])
                case .custom:
                    self.status.stringValue = t("upscale.custom")
                    then([])
                case .failed(let m):
                    self.status.stringValue = t("upscale.failed", m)
                    then([])
                }
            }
        }
    }

    /// Remet l'écran arrière à la normale quand plus rien ne l'utilise.
    func endUpscaleIfIdle() {
        guard let s = upscaleSession, !upscaleBusy, !photoBusy, launchPending == 0,
              !running(mirrors), !running(records), !liveRunning else { return }
        upscaleBusy = true
        DispatchQueue.global().async {
            resetUpscale(s.serial, s.displayId)
            DispatchQueue.main.async { self.upscaleSession = nil; self.upscaleBusy = false }
        }
    }

    /// Lance les instances scrcpy l'une après l'autre (≈2,5 s d'écart) : deux démarrages simultanés
    /// se disputent le même port de liaison adb et la première échoue.
    func launchStaggered(_ argsList: [[String]], onStart: @escaping (Process) -> Void) {
        launchGen += 1
        let gen = launchGen
        launchPending += argsList.count
        for (i, a) in argsList.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 2.5) { [weak self] in
                guard let self = self else { return }
                self.launchPending -= 1
                guard self.launchGen == gen else { return }
                let proc = spawn(a)
                try? proc.run()
                onStart(proc)
                // Stage Manager range sinon la fenêtre dans la bande latérale : on la fait passer au premier plan
                let pid = proc.processIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
    }

    /// Ouvre le miroir en direct de l'écran arrière dans le cadre du téléphone.
    func startLive(_ p: Phone, _ d: DisplayInfo, slot: (x: Int, w: Int, h: Int)?, upscaled: Bool, source: String) {
        guard let f = currentFrame else { return }
        let n = quality.numbers(upscaled: upscaled)
        let m = LiveMirror(serial: p.serial, displayId: d.id, frame: f, source: source)
        m.onEnded = { [weak self] done in self?.lives.removeAll { $0 === done } }
        lives.append(m)
        var topLeft: NSPoint?
        if let s = slot, let vis = NSScreen.main?.visibleFrame { topLeft = NSPoint(x: vis.minX + CGFloat(s.x), y: vis.maxY - 40) }
        m.start(bitrate: n.bitrate, fps: n.fps, topLeft: topLeft)
    }

    func stopLives(source: String? = nil) {
        lives.filter { source == nil || $0.source == source }.forEach { $0.stop() }
    }

    @objc func toggleMirror() {
        if running(mirrors) || liveRunning {
            launchGen += 1
            let ps = mirrors
            DispatchQueue.global().async { ps.forEach { stop($0) } }
            stopLives()
            return
        }
        if running(records) {
            let a = NSAlert()
            a.messageText = t("rec.inProgress")
            a.runModal(); return
        }
        guard let p = readyPhone(), !upscaleBusy, !photoBusy else { return }
        let ts = selectedTargets
        mirrors = []
        prepareUpscale(p, ts) { up in
            let slots = self.windowLayout(ts)
            var jobs: [[String]] = []
            for (i, d) in ts.enumerated() {
                if self.usesLive(d) { self.startLive(p, d, slot: slots[i], upscaled: up.contains(d.id), source: "mirror") }
                else { jobs.append(self.args(p, d, slot: slots[i], upscaled: up.contains(d.id))) }
            }
            self.launchStaggered(jobs) { self.mirrors.append($0) }
        }
    }

    @objc func toggleRecord() {
        if running(records) {
            launchGen += 1
            let ps = records
            DispatchQueue.global().async { ps.forEach { stop($0) } }
            stopLives(source: "record")
            status.stringValue = t("rec.saved", recFiles.map(\.lastPathComponent).joined(separator: ", "))
            return
        }
        guard let p = readyPhone(), !upscaleBusy, !photoBusy else { return }
        launchGen += 1
        mirrors.forEach { stop($0) }
        stopLives()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let ts = selectedTargets
        let st = stamp()
        recFiles = ts.map { outDir.appendingPathComponent("ecran_\($0.slug)_\(st).mp4") }
        records = []
        prepareUpscale(p, ts) { up in
            let slots = self.windowLayout(ts)
            var jobs: [[String]] = []
            for (i, d) in ts.enumerated() {
                var a = self.args(p, d, slot: slots[i], upscaled: up.contains(d.id)) + ["--record=\(self.recFiles[i].path)"]
                let live = self.usesLive(d)
                if !self.showWhileRecording || live { a.append("--no-playback") }
                if live {
                    // la vidéo sera recomposée dans le cadre à la fin ; le miroir en direct s'ouvre un peu après le démarrage de l'enregistrement
                    self.pendingFramed.append((self.recFiles[i], d.name))
                    if self.showWhileRecording {
                        let up2 = up.contains(d.id), slot = slots[i]
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if running(self.records) { self.startLive(p, d, slot: slot, upscaled: up2, source: "record") }
                        }
                    }
                }
                jobs.append(a)
            }
            self.recStart = Date()
            self.launchStaggered(jobs) { self.records.append($0) }
        }
    }

    func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    // MARK: photo

    @objc func takePhoto() {
        guard let p = readyPhone(), !upscaleBusy, !photoBusy else { return }
        let ts = selectedTargets
        let st = stamp()
        photoBusy = true
        status.stringValue = t("photo.capturing")
        prepareUpscale(p, ts) { _ in self.capture(p, ts, st) }
    }

    func capture(_ p: Phone, _ ts: [DisplayInfo], _ st: String) {
        let frame = frameWanted ? currentFrame : nil
        DispatchQueue.global().async {
            defer { DispatchQueue.main.async { self.photoBusy = false } }
            Thread.sleep(forTimeInterval: 0.5)
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            var saved: [URL] = []
            for d in ts {
                var a = ["-s", p.serial, "exec-out", "screencap", "-p"]
                if d.id != "0" {
                    guard let sf = d.localId else { self.setStatus(t("photo.noId", d.id)); return }
                    a += ["-d", sf]
                }
                let data = run(adbPath, a, mergeErr: false).data
                guard data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { self.setStatus(t("photo.noImage")); return }
                let file = outDir.appendingPathComponent("ecran_\(d.slug)_\(st).png")
                do { try data.write(to: file); saved.append(file) } catch { self.setStatus(t("photo.writeFail")); return }
                if let f = frame, d.role == .rear {
                    let framed = outDir.appendingPathComponent("ecran_\(d.slug)_\(st)_cadre.png")
                    if let png = Frames.composePhoto(data, in: f), (try? png.write(to: framed)) != nil { saved.append(framed) }
                }
            }
            self.setStatus(t("photo.done", saved.map(\.lastPathComponent).joined(separator: ", ")))
            NSWorkspace.shared.activateFileViewerSelecting(saved)
        }
    }

    @objc func openFolder() {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outDir)
    }

    // MARK: Wi-Fi

    @objc func switchToWifi() {
        guard let p = readyPhone() else { return }
        if p.isWifi { status.stringValue = t("wifi.already"); return }
        status.stringValue = t("wifi.activating")
        DispatchQueue.global().async {
            let ipOut = run(adbPath, ["-s", p.serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"]).text
            guard let ip = matches("inet (\\d+\\.\\d+\\.\\d+\\.\\d+)", in: ipOut).first?[0] else {
                self.setStatus(t("wifi.noWifi")); return
            }
            run(adbPath, ["-s", p.serial, "tcpip", "5555"])
            Thread.sleep(forTimeInterval: 2)
            let r = run(adbPath, ["connect", "\(ip):5555"]).text
            DispatchQueue.main.async {
                if r.contains("connected") {
                    self.pendingSelect = "\(ip):5555"
                    self.displaysSerial = nil
                    self.status.stringValue = t("wifi.ok", ip)
                    self.refresh()
                } else {
                    self.status.stringValue = t("wifi.failed", r.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    @objc func manualConnect() {
        let pairAddr = NSTextField(string: ""); pairAddr.placeholderString = t("manual.eg", "192.168.1.20:37123")
        let code = NSTextField(string: ""); code.placeholderString = t("manual.codeHint")
        let connAddr = NSTextField(string: ""); connAddr.placeholderString = t("manual.eg", "192.168.1.20:41234")
        let form = NSStackView(views: [
            NSTextField(labelWithString: t("manual.pairAddr")), pairAddr,
            NSTextField(labelWithString: t("manual.code")), code,
            NSTextField(labelWithString: t("manual.connAddr")), connAddr,
        ])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 4
        for f in [pairAddr, code, connAddr] { f.widthAnchor.constraint(equalToConstant: 280).isActive = true }
        form.frame = NSRect(x: 0, y: 0, width: 280, height: form.fittingSize.height)

        let a = NSAlert()
        a.messageText = t("manual.title")
        a.informativeText = t("manual.info")
        a.accessoryView = form
        a.addButton(withTitle: t("manual.connect"))
        a.addButton(withTitle: t("manual.cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let pa = pairAddr.stringValue.trimmingCharacters(in: .whitespaces)
        let pc = code.stringValue.trimmingCharacters(in: .whitespaces)
        let ca = connAddr.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ca.isEmpty else { status.stringValue = t("manual.noAddr"); return }
        status.stringValue = t("manual.connecting")
        DispatchQueue.global().async {
            if !pa.isEmpty, !pc.isEmpty {
                let r = run(adbPath, ["pair", pa, pc]).text
                if !r.contains("Successfully") {
                    self.setStatus(t("manual.pairFailed", r.trimmingCharacters(in: .whitespacesAndNewlines))); return
                }
            }
            let r = run(adbPath, ["connect", ca]).text
            DispatchQueue.main.async {
                if r.contains("connected") {
                    self.pendingSelect = ca
                    self.displaysSerial = nil
                    self.status.stringValue = t("manual.ok")
                    self.refresh()
                } else {
                    self.status.stringValue = t("manual.failed", r.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    // MARK: UI

    func tick() {
        endUpscaleIfIdle()
        exportFramedVideosIfDone()
        mirrorBtn.title = (running(mirrors) || liveRunning) ? t("mirror.stop") : t("mirror.start")
        if running(records) {
            recBtn.title = t("rec.stop")
            let s = Int(Date().timeIntervalSince(recStart))
            timerLabel.stringValue = String(format: "● REC %02d:%02d", s / 60, s % 60)
            timerLabel.isHidden = false
        } else {
            recBtn.title = t("rec.start")
            timerLabel.isHidden = true
        }
    }

    /// Quand l'enregistrement est terminé, recompose chaque vidéo de l'écran arrière dans le cadre.
    func exportFramedVideosIfDone() {
        if !running(records) { stopLives(source: "record") }
        guard !pendingFramed.isEmpty, !framedBusy, !running(records), launchPending == 0, let frame = currentFrame else { return }
        framedBusy = true
        let jobs = pendingFramed; pendingFramed = []
        status.stringValue = t("frame.exporting")
        func next(_ i: Int, _ done: [String]) {
            guard i < jobs.count else {
                framedBusy = false
                status.stringValue = t("frame.done", done.joined(separator: ", "))
                return
            }
            let src = jobs[i].src
            guard FileManager.default.fileExists(atPath: src.path) else { return next(i + 1, done) }
            let dst = src.deletingPathExtension().appendingPathExtension("tmp").deletingPathExtension()
                .deletingLastPathComponent().appendingPathComponent(src.deletingPathExtension().lastPathComponent + "_cadre.mp4")
            Frames.exportVideo(from: src, to: dst, frame: frame) { result in
                switch result {
                case .success: next(i + 1, done + [dst.lastPathComponent])
                case .failure(let e):
                    self.status.stringValue = t("frame.failed", e.localizedDescription)
                    next(i + 1, done)
                }
            }
        }
        next(0, [])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) {
        mirrors.forEach { stop($0) }; records.forEach { stop($0) }; lives.forEach { $0.stop() }
        if let s = upscaleSession { resetUpscale(s.serial, s.displayId) }   // jamais laisser le téléphone en ×2
        run(adbPath, ["kill-server"])   // notre serveur privé seulement (port 5137), jamais celui des autres outils
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// Mode de test sans interface : Rear Screen --selftest-frame photo|video <entrée> <sortie> [dossier-du-cadre]
if CommandLine.arguments.count >= 5, CommandLine.arguments[1] == "--selftest-frame" {
    let a = CommandLine.arguments
    let dir = a.count >= 6 ? URL(fileURLWithPath: a[5]) : URL(fileURLWithPath: resources).appendingPathComponent("frames/default")
    guard let f = Frames.load(dir: dir, id: "test", fallbackName: "test") else { print("cadre introuvable ou invalide : \(dir.path)"); exit(2) }
    print("cadre : \(Int(f.size.width))×\(Int(f.size.height)), écran \(f.screen)")
    if a[2] == "photo" {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: a[3])), let png = Frames.composePhoto(d, in: f) else { print("échec photo"); exit(1) }
        try? png.write(to: URL(fileURLWithPath: a[4])); print("OK photo → \(a[4])"); exit(0)
    } else {
        let sem = DispatchSemaphore(value: 0); var code: Int32 = 0
        Frames.exportVideo(from: URL(fileURLWithPath: a[3]), to: URL(fileURLWithPath: a[4]), frame: f) { r in
            if case .failure(let e) = r { print("échec vidéo : \(e.localizedDescription)"); code = 1 } else { print("OK vidéo → \(a[4])") }
            sem.signal()
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        exit(code)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
