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

// pickSentences takes whole sentences until the joined text is long enough.
var rng = SystemRandomNumberGenerator()
let four = ["aaaa", "bbbb", "cccc"].map { Quote(text: $0) }
let picked = pickSentences(from: four, chars: 6, using: &rng).map(\.text)
assert(picked.joined(separator: " ").count == 9, "picked \(picked)") // two sentences and a space
// maxChars skips sentences that would overflow it, but never leaves the round empty.
let long = String(repeating: "x", count: 20)
let capped = pickSentences(from: four + [Quote(text: long)], chars: 12, maxChars: 14, using: &rng).map(\.text)
assert(capped == [long] || capped.sorted() == ["aaaa", "bbbb", "cccc"], "capped \(capped)")

// Every stoic quote names its source and fits 90 seconds at 40 wpm (300 characters).
for lang in [Lang.es, .en] {
    let stoic = Collection.stoic.quotes(lang)
    assert(stoic.count >= 40 && stoic.allSatisfy { $0.source != nil && $0.text.count <= charsFor(wpm: 40, seconds: 90) }, "stoic \(lang)")
    let general = Collection.general.quotes(lang).map(\.text)
    assert(general.count >= 100 && Set(general).count == general.count, "general \(lang)")
}

// wrapLines breaks after spaces, keeps trailing spaces, and hard-breaks words longer than a line.
assert(wrapLines("aaa bbb ccc", width: 7) == [0..<8, 8..<11])
assert(wrapLines("aaaaaaaaaa", width: 4) == [0..<4, 4..<8, 8..<10])
assert(wrapLines("ab", width: 7) == [0..<2])

// lineWindow: three sharp lines, one dimmed on each side, the rest hidden.
let six = (0..<6).map { $0 * 10..<($0 + 1) * 10 }
let l0 = lineWindow(six, cursor: 0)
assert(l0.before == nil && l0.focus == 0..<3 && l0.after == 3, "start \(l0)")
let l3 = lineWindow(six, cursor: 35) // on the fourth line
assert(l3.before == 1 && l3.focus == 2..<5 && l3.after == 5, "middle \(l3)")
let l5 = lineWindow(six, cursor: 60) // end of text
assert(l5.before == 2 && l5.focus == 3..<6 && l5.after == nil, "end \(l5)")
let two = lineWindow([0..<5, 5..<9], cursor: 6)
assert(two.before == nil && two.focus == 0..<2 && two.after == nil, "short \(two)")

// Session counts corrected errors and saves the finished round.
let historyURL = tempDir().appendingPathComponent("history.json")
let session = Session(history: History(url: historyURL), folder: tempDir())
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
assert(session.correct == 2 && session.errors == 1, "correct \(session.correct) errors \(session.errors)")
assert(!session.isRecord, "no record on the very first round")

// A round is a record only when it beats every saved round (the first one was 24 wpm).
func finishedRound(seconds: Double) -> Session {
    let s = Session(history: History(url: historyURL), folder: tempDir())
    s.target = "ab"
    s.type("a", now: t0)
    s.type("ab", now: t0.addingTimeInterval(seconds))
    return s
}
assert(finishedRound(seconds: 0.5).isRecord, "48 wpm beats 24")
assert(!finishedRound(seconds: 2).isRecord, "12 wpm is below the best")

// A corrupt history file is kept aside instead of overwritten.
let dir = tempDir()
let corrupt = dir.appendingPathComponent("history.json")
try! Data("not json".utf8).write(to: corrupt)
var history = History(url: corrupt)
try! history.add(RoundResult(date: Date(), lang: .es, wpm: 50, accuracy: 1, seconds: 40))
assert(try! FileManager.default.contentsOfDirectory(atPath: dir.path).count == 2)


// recentWPMs: the last 20 saved rounds, oldest first, ending with the round just finished.
let chartURL = tempDir().appendingPathComponent("history.json")
var chartHistory = History(url: chartURL)
for i in 0..<25 { try! chartHistory.add(RoundResult(date: Date(), lang: .es, wpm: Double(i), accuracy: 1, seconds: 30)) }
let chart = Session(history: chartHistory, folder: tempDir())
chart.target = "ab"
chart.type("a", now: t0)
chart.type("ab", now: t0.addingTimeInterval(6))
assert(chart.recentWPMs.count == 20 && chart.recentWPMs.first == 6 && chart.recentWPMs.last == chart.result?.wpm, "chart \(chart.recentWPMs)")

// The source follows the sentence under the cursor.
let sourced = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: tempDir())
sourced.choose(.stoic)
assert(sourced.quotes.count > 0 && sourced.source == sourced.quotes[0].source, "first source")
if sourced.quotes.count > 1 {
    sourced.type(String(sourced.target.prefix(sourced.quotes[0].text.count + 1)), now: t0)
    assert(sourced.source == sourced.quotes[1].source, "second source")
}

// Picker: every letter filters (accent- and case-insensitive), moving is clamped, ⏎ chooses.
UserDefaults.standard.removeObject(forKey: "favorites")
let picker = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: tempDir())
picker.choose(.general)
picker.openPicker()
assert(picker.picking && picker.selection == 0)
picker.movePicker(-1)
assert(picker.selection == 0, "stops at the top")
picker.movePicker(1)
picker.movePicker(1)
assert(picker.selection == 1, "stops at the bottom")
picker.typeInPicker("j")
assert(picker.filter == "j" && picker.selection == 0, "j types into the filter")
picker.deleteInPicker()
picker.typeInPicker("E")
picker.typeInPicker("s")
picker.typeInPicker("t")
assert(picker.matches.map(\.id) == ["stoic"] && picker.selection == 0, "filter \(picker.matches.map(\.id))")
picker.typeInPicker("k")
assert(picker.filter == "Estk" && picker.matches.isEmpty, "k types into the filter")
picker.choosePicked()
assert(picker.picking && picker.collection.id == "general", "nothing to choose keeps the picker open")
picker.deleteInPicker()
picker.choosePicked()
assert(!picker.picking && picker.collection.id == "stoic" && picker.quotes.allSatisfy { $0.source != nil }, "chose stoic")
picker.openPicker()
assert(picker.selection == 1, "opens on the current collection")
picker.typeInPicker("GENERAL")
assert(picker.matches.map(\.id) == ["general"])
picker.closePicker()
assert(!picker.picking && picker.collection.id == "stoic", "esc keeps the collection")

// User collections: a JSON file with a name and sentences, used whatever the language.
let valid = Data(#"{"name": " Programación ", "quotes": [{"text": " Talk is cheap. ", "source": "Linus Torvalds"}, {"text": "Sin fuente."}]}"#.utf8)
let parsed = try! Collection.parse(valid, id: "file:p.json")
assert(parsed.collection.name == "Programación" && parsed.skipped == 0, "parsed \(parsed)")
assert(parsed.collection.es == [Quote(text: "Talk is cheap.", source: "Linus Torvalds"), Quote(text: "Sin fuente.")], "quotes \(parsed.collection.es)")
assert(parsed.collection.es == parsed.collection.en)
let tooLong = String(repeating: "x", count: Collection.maxChars + 1)
let trimmed = try! Collection.parse(Data(#"{"name": "A", "quotes": [{"text": "ok"}, {"text": "  "}, {"text": "\#(tooLong)"}]}"#.utf8), id: "a")
assert(Collection.maxChars == 300 && trimmed.collection.es.map(\.text) == ["ok"] && trimmed.skipped == 2, "skipped \(trimmed.skipped)")

// load: broken files become problems, the valid one still loads.
let folder = tempDir()
try! valid.write(to: folder.appendingPathComponent("prog.json"))
try! Data("not json".utf8).write(to: folder.appendingPathComponent("bad.json"))
try! Data(#"{"name": "Sin frases"}"#.utf8).write(to: folder.appendingPathComponent("empty.json"))
try! Data("ignored".utf8).write(to: folder.appendingPathComponent("notes.txt"))
let loaded = Collection.load(from: folder)
assert(loaded.collections.map(\.id) == ["file:prog.json"], "loaded \(loaded.collections.map(\.id))")
assert(loaded.problems.count == 2 && loaded.problems.allSatisfy { $0.hasPrefix("bad.json") || $0.hasPrefix("empty.json") }, "problems \(loaded.problems)")

// A Session lists file collections after the built-ins and practices with them.
let user = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: folder)
assert(user.collections.map(\.id) == ["general", "stoic", "file:prog.json"] && user.problems.count == 2, "collections \(user.collections.map(\.id))")
user.choose(user.collections[2])
assert(user.quotes.allSatisfy { parsed.collection.es.contains($0) } && !user.quotes.isEmpty, "file quotes \(user.quotes)")

// Favorites come first; ⌃f keeps the same collection selected as it moves.
user.openPicker()
assert(user.selection == 2)
user.toggleFavoritePicked()
assert(user.matches.map(\.id) == ["file:prog.json", "general", "stoic"] && user.selection == 0, "favorite first \(user.matches.map(\.id))")
user.toggleFavoritePicked()
assert(user.matches.map(\.id) == ["general", "stoic", "file:prog.json"] && user.selection == 2, "unfavorited")
user.closePicker()

// A chosen file collection whose file is deleted falls back to General.
try! FileManager.default.removeItem(at: folder.appendingPathComponent("prog.json"))
user.reloadCollections()
assert(user.collection.id == "general" && user.collections.count == 2, "fallback \(user.collection.id)")
UserDefaults.standard.removeObject(forKey: "favorites")

// The documented example parses.
let example = try! Collection.parse(Data(contentsOf: URL(fileURLWithPath: "Examples/Programming.json")), id: "file:Programming.json")
assert(example.skipped == 0 && example.collection.es.count >= 8 && example.collection.es.allSatisfy { $0.source != nil }, "example")

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
