// Renders the README screenshots and demo GIF from the real TyperView and Session.
// Run src/mac/readme-assets.sh; output goes to docs/assets. Uses a temporary history and settings,
// never the user's. The round is typed in real time, so the live and final WPM are real numbers.
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aiber-readme-\(UUID().uuidString)")

/// The desk behind the card: darker than the card, with the brand glow.
struct Desk<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .padding(40)
            .background {
                ZStack {
                    Color(0x120A0C)
                    RadialGradient(colors: [G.pink.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                    RadialGradient(colors: [G.neon.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 460)
                }
            }
            .environment(\.colorScheme, .dark)
    }
}

@MainActor func render(_ session: Session, scale: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: Desk { TyperView(session: session, onImport: {}, onClose: {}) })
    renderer.scale = scale
    return renderer.cgImage!
}

func writePNG(_ image: CGImage, _ name: String) {
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
    print("wrote \(name)")
}

func writeGIF(_ frames: [(image: CGImage, delay: Double)], _ name: String) {
    let url = out.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
        let delay = [kCGImagePropertyGIFDelayTime: frame.delay, kCGImagePropertyGIFUnclampedDelayTime: frame.delay]
        CGImageDestinationAddImage(dest, frame.image, [kCGImagePropertyGIFDictionary: delay] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(dest))
    print("wrote \(name) (\(frames.count) frames)")
}

/// A session on the Stoicism collection with a short, rising history in a temporary folder.
func makeSession(_ lang: Lang) throws -> Session {
    let dir = scratch.appendingPathComponent(lang.rawValue)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var history = History(url: dir.appendingPathComponent("history.json"))
    for (i, wpm) in [48.0, 51, 50, 55, 53, 58, 57, 61, 60, 63, 62, 66].enumerated() {
        try history.add(RoundResult(date: Date(timeIntervalSinceNow: Double(i - 12) * 86_400), lang: lang, wpm: wpm, accuracy: 0.95, seconds: 45))
    }
    let defaults = UserDefaults(suiteName: "aiber-readme-\(UUID().uuidString)")!
    defaults.set(lang.rawValue, forKey: "lang")
    defaults.set("stoic", forKey: "pack")
    defaults.set(["stoic", "programming"], forKey: "favorites")
    return Session(history: history, folder: dir.appendingPathComponent("Colecciones"), defaults: defaults)
}

/// Keystrokes at ~78 wpm with jitter: the field's whole text at each moment, plus three typos fixed with backspace.
func schedule(_ target: String) -> (events: [(t: Double, text: String, typo: Bool)], end: Double) {
    let chars = Array(target)
    let typos = [0.1, 0.45, 0.75].map { f in (Int(Double(chars.count) * f)..<chars.count).first { chars[$0].isLowercase }! }
    var rng = SystemRandomNumberGenerator()
    var t = 0.6, events: [(t: Double, text: String, typo: Bool)] = []
    func step() -> Double { 60 / (78 * 5) * Double.random(in: 0.6...1.4, using: &rng) }
    for i in chars.indices {
        let typed = String(chars[..<i])
        if typos.contains(i) {
            let wrong: Character = chars[i] == "e" ? "r" : "e"
            events.append((t, typed + String(wrong), true)); t += step() * 2
            events.append((t, typed, false)); t += step()
        }
        events.append((t, typed + String(chars[i]), false))
        t += step() * (chars[i] == " " && Int.random(in: 0..<6) == 0 ? 2.5 : 1)
    }
    return (events, t)
}

@MainActor func run(_ lang: Lang) throws {
    let session = try makeSession(lang)
    // The UI is in Spanish whatever the language, so the picker and the results are shot once.
    let shared = lang == .en
    if shared {
        session.openPicker()
        writePNG(render(session, scale: 2), "picker.png")
        session.closePicker()
    }

    let gifScale: CGFloat = 1.5
    let plan = schedule(session.round.target)
    // Keep the first seconds and the last one of the round; the middle is cut from the GIF.
    func kept(_ t: Double) -> Bool { t < 9 || t > plan.end - 1.2 }
    var frames: [(image: CGImage, delay: Double)] = [(render(session, scale: gifScale), 1)]
    var lastFrame = -1.0, shotTaken = false
    let start = Date()
    for event in plan.events {
        while true {
            let now = Date().timeIntervalSince(start)
            if now >= event.t { break }
            if kept(now), now - lastFrame >= 0.1 {
                if let last = frames.indices.last, lastFrame >= 0 { frames[last].delay = kept(lastFrame) && now - lastFrame < 1 ? now - lastFrame : 0.1 }
                frames.append((render(session, scale: gifScale), 0.1))
                lastFrame = now
            } else {
                Thread.sleep(forTimeInterval: 0.004)
            }
        }
        session.type(event.text)
        // The static shot shows the typo in the middle of the round.
        if event.typo, !shotTaken, session.round.typed.count > session.round.target.count / 3 {
            writePNG(render(session, scale: 2), "typing-\(lang.rawValue).png")
            shotTaken = true
        }
    }
    if shared { writePNG(render(session, scale: 2), "results.png") }
    frames.append((render(session, scale: gifScale), 4))
    writeGIF(frames, "demo-\(lang.rawValue).gif")
    if let r = session.result { print("\(lang.rawValue): \(Int(r.wpm)) wpm, \(Int(r.accuracy * 100))%, \(Int(r.seconds)) s") }
}

@MainActor func banners(_ lang: Lang) {
    let copy = BannerCopy.of(lang)
    let frames = bannerFrames(copy).map { frame in
        let renderer = ImageRenderer(content: frame.view)
        renderer.scale = 1.5
        return (renderer.cgImage!, frame.delay)
    }
    writeGIF(frames, "banner-\(lang.rawValue).gif")
    let alt = ImageRenderer(content: IconBanner(copy: copy))
    alt.scale = 2
    writePNG(alt.cgImage!, "banner-alt-\(lang.rawValue).png")
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try MainActor.assumeIsolated {
    for lang in [Lang.en, .es] { banners(lang) }
    // shortcut: "banners" skips the demo rounds, which take about two minutes.
    if CommandLine.arguments.count < 3 || CommandLine.arguments[2] != "banners" {
        for lang in [Lang.en, .es] { try run(lang) }
    }
}
try? FileManager.default.removeItem(at: scratch)
