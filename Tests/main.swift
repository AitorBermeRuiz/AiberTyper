// Self-check for the typing logic. These Command Line Tools lack swift-testing's macro plugin,
// so run it with ./test.sh instead of `swift test`.
import AppKit

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// Score: WPM from correct characters, accuracy from keystrokes.
let s = score(target: "hola mundo", typed: "hola mundx", seconds: 6, keystrokes: 10, errors: 1)
assert(abs(s.wpm - 18) < 0.001, "wpm \(s.wpm)") // 9 correct chars / 5 / 0.1 min
assert(abs(s.accuracy - 0.9) < 0.001, "accuracy \(s.accuracy)")

// makeText joins whole sentences until long enough.
var rng = SystemRandomNumberGenerator()
let text = makeText(from: ["aaaa", "bbbb", "cccc"], chars: 6, using: &rng)
assert(text.count == 9, "text \(text)") // two sentences and a space

// Session counts corrected errors and saves the finished round.
let historyURL = tempDir().appendingPathComponent("history.json")
let session = Session(history: History(url: historyURL))
session.target = "añ"
let t0 = Date()
assert(session.live(now: t0) == nil, "no live stats before the first keystroke")
session.type("x", now: t0)
session.type("", now: t0)
session.type("a", now: t0)
let live = session.live(now: t0.addingTimeInterval(6))!
assert(abs(live.wpm - 2) < 0.001 && abs(live.accuracy - 0.5) < 0.001, "live \(live)") // 1 correct char in 0.1 min; 1 of 2 keystrokes wrong
session.type("añ", now: t0.addingTimeInterval(1))
assert(abs((session.result?.accuracy ?? 0) - 2.0 / 3) < 0.001, "accuracy \(String(describing: session.result))")
assert(History(url: historyURL).rounds.count == 1)

// A corrupt history file is kept aside instead of overwritten.
let dir = tempDir()
let corrupt = dir.appendingPathComponent("history.json")
try! Data("not json".utf8).write(to: corrupt)
var history = History(url: corrupt)
try! history.add(RoundResult(date: Date(), lang: .es, wpm: 50, accuracy: 1, seconds: 40))
assert(try! FileManager.default.contentsOfDirectory(atPath: dir.path).count == 2)

// HotKey: only combinations with ⌘, ⌥ or ⌃ are accepted, and the label lists the modifiers in macOS order.
func keyEvent(_ chars: String, code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}
assert(HotKey(event: keyEvent("t", code: 17, [])) == nil && HotKey(event: keyEvent("T", code: 17, .shift)) == nil, "needs ⌘, ⌥ or ⌃")
let recorded = HotKey(event: keyEvent("t", code: 17, [.option, .shift]))
assert(recorded == .standard && recorded?.label == "⌥⇧T", "recorded \(String(describing: recorded))")
assert(HotKey(event: keyEvent(" ", code: 49, [.command, .control]))?.label == "⌃⌘Espacio")

print("self-check OK")
