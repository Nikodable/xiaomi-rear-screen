import Cocoa
import AVFoundation
import CoreMedia

// Miroir en direct dans un cadre de téléphone.
// On lit nous-mêmes le flux H.264 du serveur scrcpy (protocole ci-dessous) et on l'affiche avec AVSampleBufferDisplayLayer
// (décodage matériel par macOS), dans une fenêtre sans bordure en forme de téléphone. Vue seule : pas de pilotage tactile.
//
// Protocole du flux vidéo (scrcpy 4.x, mode « forward », sans audio ni contrôle) :
//   1 octet factice · nom de l'appareil (64 octets) · identifiant du codec (4 octets, « h264 »)
//   puis des paquets de 12 octets d'en-tête (trois entiers 32 bits, grand-boutiste) :
//     a & 0x80000000 → paquet de session : b = largeur, c = hauteur
//     sinon          → a & 0x40000000 = configuration (SPS/PPS), a & 0x20000000 = image clé ; c = taille des données (Annex-B)

/// Doit correspondre au scrcpy-server embarqué.
let scrcpyServerVersion = "4.1"

final class LiveFrameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onCloseRequest: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCloseRequest?() }      // touche Échap
    override func performClose(_ sender: Any?) { onCloseRequest?() }
}

/// Vue qui laisse passer les clics (le cadre est une simple image par-dessus la vidéo).
final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class FrameHostView: NSView {
    let closeButton = NSButton()
    var onClose: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var grabOffset: NSPoint?

    func installCloseButton() {
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: t("live.close"))
        closeButton.contentTintColor = NSColor(white: 1, alpha: 0.9)
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.toolTip = t("live.close")
        closeButton.target = self; closeButton.action = #selector(closeTapped)
        closeButton.frame = NSRect(x: bounds.width - 40, y: bounds.height - 40, width: 28, height: 28)
        closeButton.alphaValue = 0
        addSubview(closeButton)
    }
    @objc private func closeTapped() { onClose?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(a); tracking = a
    }
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { grabOffset = event.locationInWindow }       // où on a saisi le téléphone
    override func mouseDragged(with event: NSEvent) {
        guard let w = window, let g = grabOffset else { return }
        let m = NSEvent.mouseLocation                                                           // position de la souris sur l'écran
        w.setFrameOrigin(NSPoint(x: m.x - g.x, y: m.y - g.y))
    }
    override func mouseUp(with event: NSEvent) { grabOffset = nil }
    override func mouseEntered(with event: NSEvent) { closeButton.animator().alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { closeButton.animator().alphaValue = 0 }
    override func rightMouseDown(with event: NSEvent) {
        let m = NSMenu()
        let item = NSMenuItem(title: t("live.close"), action: #selector(closeTapped), keyEquivalent: "")
        item.target = self; m.addItem(item)
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }
}

final class LiveMirror: NSObject {
    let serial: String
    let displayId: String
    let frame: PhoneFrame
    let source: String                           // "mirror" ou "record" : qui a ouvert cette fenêtre
    var onEnded: ((LiveMirror) -> Void)?
    private(set) var isRunning = true

    private let lock = NSLock()
    private var window: LiveFrameWindow?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var server: Process?
    private var port = 0
    private var sock: Int32 = -1
    private var formatDesc: CMVideoFormatDescription?
    private var failure: String?

    init(serial: String, displayId: String, frame: PhoneFrame, source: String) {
        self.serial = serial; self.displayId = displayId; self.frame = frame; self.source = source
    }

    // MARK: cycle de vie

    /// À appeler sur le thread principal.
    func start(bitrate: Int, fps: Int, topLeft: NSPoint?) {
        buildWindow(topLeft: topLeft)
        Thread { [weak self] in self?.pump(bitrate: bitrate, fps: fps) }.start()
    }

    /// Idempotent, utilisable depuis n'importe quel thread.
    func stop() {
        lock.lock()
        guard isRunning else { lock.unlock(); return }
        isRunning = false
        let s = sock, srv = server, p = port
        lock.unlock()
        if s >= 0 { shutdown(s, SHUT_RDWR) }                  // débloque la lecture ; le thread ferme la socket
        srv?.terminate()
        if p > 0 { DispatchQueue.global().async { [serial] in run(adbPath, ["-s", serial, "forward", "--remove", "tcp:\(p)"]) } }
        DispatchQueue.main.async {
            self.window?.orderOut(nil); self.window = nil
            self.onEnded?(self)
        }
    }

    // MARK: fenêtre

    private func buildWindow(topLeft: NSPoint?) {
        let fw = frame.size.width, fh = frame.size.height
        let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = min(1, min(900, vis.width * 0.8) / fw, min(800, vis.height * 0.9) / fh)
        let size = NSSize(width: (fw * scale).rounded(), height: (fh * scale).rounded())

        let win = LiveFrameWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = frame.transparentBackground         // l'ombre épouse la forme du téléphone
        win.isMovableByWindowBackground = true
        win.title = frame.name
        win.isReleasedWhenClosed = false
        win.onCloseRequest = { [weak self] in self?.stop() }

        let host = FrameHostView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        if !frame.transparentBackground { host.layer?.backgroundColor = CGColor(gray: 0, alpha: 1) }
        host.onClose = { [weak self] in self?.stop() }

        let s = frame.screen
        let vr = NSRect(x: s.minX * scale, y: (fh - s.maxY) * scale, width: s.width * scale, height: s.height * scale)
        let videoView = NSView(frame: vr)
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        displayLayer.frame = videoView.bounds
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        videoView.layer?.addSublayer(displayLayer)

        let overlay = PassThroughView(frame: host.bounds)
        overlay.wantsLayer = true
        overlay.layer?.contents = frame.image
        overlay.layer?.contentsGravity = .resize
        overlay.layer?.minificationFilter = .trilinear

        host.addSubview(videoView)
        host.addSubview(overlay)            // le cadre par-dessus : sa zone opaque masque les coins de l'écran
        host.installCloseButton()
        win.contentView = host

        if let o = topLeft { win.setFrameTopLeftPoint(o) } else { win.center() }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    // MARK: flux

    private func fail(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            let a = NSAlert(); a.messageText = t("live.failed", message); a.runModal()
        }
        stop()
    }

    private func pump(bitrate: Int, fps: Int) {
        let jar = "/data/local/tmp/scrcpy-server-live.jar"
        run(adbPath, ["-s", serial, "push", resources + "/scrcpy-server", jar])
        let scid = String(format: "%08x", UInt32.random(in: 1...0x7fffffff))
        let fw = run(adbPath, ["-s", serial, "forward", "tcp:0", "localabstract:scrcpy_" + scid]).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = Int(fw) else { return fail("adb forward (\(fw.prefix(80)))") }
        lock.lock(); port = p; lock.unlock()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments = ["-s", serial, "shell",
                          "CLASSPATH=\(jar) app_process / com.genymobile.scrcpy.Server \(scrcpyServerVersion) scid=\(scid) log_level=info "
                          + "video=true audio=false control=false tunnel_forward=true video_codec=h264 "
                          + "video_bit_rate=\(bitrate) max_fps=\(fps) display_id=\(displayId)"]
        proc.environment = scrcpyEnv()
        proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return fail(error.localizedDescription) }
        lock.lock(); server = proc; lock.unlock()

        // connexion : le serveur met ~0,5 s à ouvrir sa socket ; il envoie un octet factice dès qu'on est connecté
        var fd: Int32 = -1
        let t0 = Date()
        while isRunning && Date().timeIntervalSince(t0) < 12 {
            let c = connectLocal(port: p)
            if c >= 0 {
                var dummy: UInt8 = 0
                if readExactly(c, &dummy, 1, retryOnTimeout: false) { fd = c; break }
                close(c)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard isRunning else { if fd >= 0 { close(fd) }; return }
        guard fd >= 0 else { return fail("timeout") }
        lock.lock(); sock = fd; lock.unlock()
        defer { close(fd) }

        var head = [UInt8](repeating: 0, count: 68)                  // nom (64) + codec (4)
        guard readExactly(fd, &head, 68) else { return stopIfRunning("stream header") }
        guard String(bytes: head[64..<68], encoding: .ascii) == "h264" else { return fail("codec") }

        var hdr = [UInt8](repeating: 0, count: 12)
        while isRunning {
            guard readExactly(fd, &hdr, 12) else { break }
            let a = be32(hdr, 0), b = be32(hdr, 4), c = be32(hdr, 8)
            if a & 0x80000000 != 0 {                                   // paquet de session : la taille de l'écran change
                DispatchQueue.main.async { [weak self] in self?.displayLayer.flushAndRemoveImage() }
                continue
            }
            guard c > 0, c < 32_000_000 else { break }
            var payload = [UInt8](repeating: 0, count: Int(c))
            guard readExactly(fd, &payload, Int(c)) else { break }
            handle(payload, isConfig: a & 0x40000000 != 0, isKey: a & 0x20000000 != 0)
            _ = b
        }
        stop()
    }

    private func stopIfRunning(_ why: String) { if isRunning { fail(why) } }

    // MARK: décodage / affichage

    private func handle(_ payload: [UInt8], isConfig: Bool, isKey: Bool) {
        let nals = splitAnnexB(payload)
        var sps: [UInt8]?, pps: [UInt8]?
        var avcc = [UInt8]()
        for n in nals where !n.isEmpty {
            switch n[0] & 0x1f {
            case 7: sps = n
            case 8: pps = n
            case 9: break                                              // délimiteur d'unité d'accès
            default:
                let len = UInt32(n.count)
                avcc += [UInt8(len >> 24), UInt8((len >> 16) & 0xff), UInt8((len >> 8) & 0xff), UInt8(len & 0xff)] + n
            }
        }
        if let sps = sps, let pps = pps { updateFormat(sps: sps, pps: pps) }
        guard !isConfig, !avcc.isEmpty, let fd = formatDesc, let sb = makeSampleBuffer(avcc, fd) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            if self.displayLayer.status == .failed { self.displayLayer.flush() }
            if isKey || self.displayLayer.isReadyForMoreMediaData { self.displayLayer.enqueue(sb) }
        }
    }

    private func updateFormat(sps: [UInt8], pps: [UInt8]) {
        var fd: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBufferPointer { sp in
            pps.withUnsafeBufferPointer { pp in
                let ptrs: [UnsafePointer<UInt8>] = [sp.baseAddress!, pp.baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: ptrs,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
            }
        }
        if status == noErr, let fd = fd { formatDesc = fd }
    }

    private func makeSampleBuffer(_ data: [UInt8], _ fd: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: data.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
              let bb = block,
              data.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: data.count) }) == kCMBlockBufferNoErr
        else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var size = data.count
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: bb, formatDescription: fd, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sb) == noErr, let buf = sb else { return nil }
        if let atts = CMSampleBufferGetSampleAttachmentsArray(buf, createIfNecessary: true) as? [NSMutableDictionary], let d = atts.first {
            d[kCMSampleAttachmentKey_DisplayImmediately] = true     // pas de tampon de resynchronisation : affichage direct
        }
        return buf
    }
}

// MARK: utilitaires bas niveau

private func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
    (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
}

/// Découpe un flux Annex-B (codes de début 00 00 01 / 00 00 00 01) en unités NAL.
private func splitAnnexB(_ d: [UInt8]) -> [[UInt8]] {
    var starts: [Int] = [], i = 0
    while i + 2 < d.count {
        if d[i] == 0, d[i + 1] == 0, d[i + 2] == 1 { starts.append(i + 3); i += 3 } else { i += 1 }
    }
    var out: [[UInt8]] = []
    for (k, s) in starts.enumerated() {
        var e = k + 1 < starts.count ? starts[k + 1] - 3 : d.count
        while e > s, d[e - 1] == 0 { e -= 1 }                          // le 0 du code de début à 4 octets appartient au séparateur
        if e > s { out.append(Array(d[s..<e])) }
    }
    return out
}

private func connectLocal(port: Int) -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    var tv = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(UInt16(port).bigEndian)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let r = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    if r != 0 { close(fd); return -1 }
    return fd
}

/// Lit exactement `count` octets ; false si la connexion est fermée ou en erreur.
private func readExactly(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ count: Int, retryOnTimeout: Bool = true) -> Bool {
    var got = 0
    while got < count {
        let n = recv(fd, buf + got, count - got, 0)
        if n > 0 { got += n }
        else if n < 0 && errno == EINTR { continue }
        else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            if retryOnTimeout { continue }                          // flux vivant mais silencieux : on attend
            return false                                            // poignée de main : on abandonne après le délai
        }
        else { return false }
    }
    return true
}
private func readExactly(_ fd: Int32, _ buf: inout UInt8, _ count: Int, retryOnTimeout: Bool = true) -> Bool {
    withUnsafeMutablePointer(to: &buf) { readExactly(fd, $0, count, retryOnTimeout: retryOnTimeout) }
}
private func readExactly(_ fd: Int32, _ buf: inout [UInt8], _ count: Int) -> Bool {
    buf.withUnsafeMutableBytes { readExactly(fd, $0.baseAddress!, count) }
}
