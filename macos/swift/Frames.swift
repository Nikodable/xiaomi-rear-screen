import Cocoa
import AVFoundation

// Cadres de téléphone : chargement (cadre par défaut livré avec l'app + cadres de l'utilisateur),
// composition d'une photo et export vidéo dans le cadre.

/// Cadre : image RGBA avec une zone transparente à la place de l'écran.
struct PhoneFrame {
    let id: String              // "default" ou nom du dossier
    let name: String
    let image: CGImage
    let size: CGSize            // taille de l'image, en pixels
    let screen: CGRect          // position de l'écran dans l'image (origine en haut à gauche), en pixels
    let radius: CGFloat
    let transparentBackground: Bool
}

enum Frames {
    static let defaultId = "default"
    static let noneId = "none"            // « Aucun cadre » : choix toujours disponible, et valeur par défaut

    /// ~/Library/Application Support/Rear Screen/frames
    static var userDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rear Screen/frames", isDirectory: true)
    }

    /// Le cadre par défaut d'abord, puis ceux du dossier de l'utilisateur (ordre alphabétique).
    static func loadAll() -> [PhoneFrame] {
        var out: [PhoneFrame] = []
        let bundled = URL(fileURLWithPath: resources).appendingPathComponent("frames/default", isDirectory: true)
        if let f = load(dir: bundled, id: defaultId, fallbackName: t("frame.default")) { out.append(f) }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for d in dirs.sorted(by: { $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending }) {
            guard (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let f = load(dir: d, id: d.lastPathComponent, fallbackName: d.lastPathComponent) else { continue }
            out.append(f)
        }
        return out
    }

    /// Lit `frame.png` + `frame.json` ; nil si le dossier est incomplet ou invalide.
    static func load(dir: URL, id: String, fallbackName: String) -> PhoneFrame? {
        let png = dir.appendingPathComponent("frame.png"), json = dir.appendingPathComponent("frame.json")
        guard let src = CGImageSourceCreateWithURL(png as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let data = try? Data(contentsOf: json),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scr = obj["screen"] as? [String: Any],
              let sx = (scr["x"] as? NSNumber)?.doubleValue, let sy = (scr["y"] as? NSNumber)?.doubleValue,
              let sw = (scr["w"] as? NSNumber)?.doubleValue, let sh = (scr["h"] as? NSNumber)?.doubleValue,
              sw > 0, sh > 0 else { return nil }
        // les coordonnées du JSON sont celles de l'image d'origine : on les ramène à la taille réelle du PNG
        let jw = (obj["width"] as? NSNumber)?.doubleValue ?? Double(img.width)
        let k = jw > 0 ? Double(img.width) / jw : 1
        let rect = CGRect(x: sx * k, y: sy * k, width: sw * k, height: sh * k)
        guard rect.maxX <= Double(img.width) + 1, rect.maxY <= Double(img.height) + 1 else { return nil }
        let name = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        return PhoneFrame(id: id, name: id == defaultId ? fallbackName : name, image: img,
                          size: CGSize(width: img.width, height: img.height), screen: rect,
                          radius: CGFloat(((scr["radius"] as? NSNumber)?.doubleValue ?? 0) * k),
                          transparentBackground: (obj["background"] as? String) == "transparent")
    }

    // MARK: photo

    /// Insère la capture d'écran dans le cadre et retourne un PNG.
    static func composePhoto(_ screenshot: Data, in frame: PhoneFrame) -> Data? {
        guard let src = NSBitmapImageRep(data: screenshot)?.cgImage else { return nil }
        let w = Int(frame.size.width), h = Int(frame.size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        if !frame.transparentBackground { ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(full) }
        // CoreGraphics a l'origine en bas à gauche
        let r = CGRect(x: frame.screen.minX, y: CGFloat(h) - frame.screen.maxY, width: frame.screen.width, height: frame.screen.height)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(r)
        let k = min(r.width / CGFloat(src.width), r.height / CGFloat(src.height))
        let dw = CGFloat(src.width) * k, dh = CGFloat(src.height) * k
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: r.midX - dw / 2, y: r.midY - dh / 2, width: dw, height: dh))
        ctx.draw(frame.image, in: full)           // le cadre par-dessus : ses bords opaques masquent les coins de l'écran
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }

    // MARK: vidéo

    /// Recompose un .mp4 (image de l'écran) dans le cadre ; `done` est appelé sur le thread principal.
    static func exportVideo(from src: URL, to dst: URL, frame: PhoneFrame, done: @escaping (Result<Void, Error>) -> Void) {
        func fail(_ m: String) { DispatchQueue.main.async { done(.failure(NSError(domain: "RearScreen", code: 1, userInfo: [NSLocalizedDescriptionKey: m]))) } }
        let asset = AVURLAsset(url: src)
        guard let vt = asset.tracks(withMediaType: .video).first else { return fail("no video track") }
        let comp = AVMutableComposition()
        guard let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return fail("track") }
        do { try ct.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: vt, at: .zero) }
        catch { return fail(error.localizedDescription) }

        let W = CGFloat(Int(frame.size.width) & ~1), H = CGFloat(Int(frame.size.height) & ~1)     // dimensions paires (H.264)
        let nat = vt.naturalSize.applying(vt.preferredTransform)
        let vw = abs(nat.width), vh = abs(nat.height)
        guard vw > 0, vh > 0 else { return fail("video size") }
        // l'image est ajustée au rectangle de l'écran (origine en haut à gauche pour les transformations vidéo)
        let r = frame.screen
        let k = min(r.width / vw, r.height / vh)
        let tx = r.midX - vw * k / 2, ty = r.midY - vh * k / 2

        let li = AVMutableVideoCompositionLayerInstruction(assetTrack: ct)
        li.setTransform(vt.preferredTransform.concatenating(CGAffineTransform(scaleX: k, y: k)).concatenating(CGAffineTransform(translationX: tx, y: ty)), at: .zero)
        let inst = AVMutableVideoCompositionInstruction()
        inst.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
        inst.layerInstructions = [li]
        let vc = AVMutableVideoComposition()
        vc.renderSize = CGSize(width: W, height: H)
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.instructions = [inst]

        let parent = CALayer(); parent.frame = CGRect(x: 0, y: 0, width: W, height: H)
        let videoLayer = CALayer(); videoLayer.frame = parent.frame
        let overlay = CALayer(); overlay.frame = parent.frame
        overlay.contents = frame.image; overlay.contentsGravity = .resize
        parent.addSublayer(videoLayer); parent.addSublayer(overlay)
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { return fail("export session") }
        try? FileManager.default.removeItem(at: dst)
        ex.outputURL = dst; ex.outputFileType = .mp4; ex.videoComposition = vc
        ex.exportAsynchronously {
            DispatchQueue.main.async {
                if ex.status == .completed { done(.success(())) }
                else { done(.failure(ex.error ?? NSError(domain: "RearScreen", code: 2, userInfo: [NSLocalizedDescriptionKey: "export \(ex.status.rawValue)"]))) }
            }
        }
    }
}
