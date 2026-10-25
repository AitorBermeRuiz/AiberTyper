// Self-check for the typing logic. These Command Line Tools lack swift-testing's macro plugin,
// so run it with ./test.sh instead of `swift test`.
import AppKit
import Carbon

var suites: [String] = []
/// A settings store of its own, so no Session sees another one's language, collection or favorites.
func freshDefaults() -> UserDefaults {
    let name = "aibertyper.selfcheck.\(UUID().uuidString)"
    suites.append(name)
    return UserDefaults(suiteName: name)!
}

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

extension Session {
    /// Starts a round whose text is exactly `text`: a one-quote collection always yields that quote.
    func practice(_ text: String) { choose(Collection(id: "test", name: "Test", es: [Quote(text: text)], en: [Quote(text: text)])) }
}

let t0 = Date()

// Round score: WPM from correct characters, accuracy from keystrokes; the completing keystroke returns it once.
var scored = Round(quotes: [Quote(text: "hola mundo")])
assert(scored.type("hola mund", now: t0) == nil, "not complete yet")
let s = scored.type("hola mundx", now: t0.addingTimeInterval(6))!
assert(abs(s.wpm - 18) < 0.001 && abs(s.accuracy - 0.9) < 0.001 && s.seconds == 6, "score \(s)") // 9 correct chars / 5 / 0.1 min
assert(scored.type("hola mundo", now: t0.addingTimeInterval(7)) == nil && scored.typed == "hola mundx", "typing after the end is ignored")

// Round counts corrected errors: a deleted wrong keystroke still costs accuracy.
var corrected = Round(quotes: [Quote(text: "añ")])
assert(corrected.live(now: t0) == nil, "no live stats before the first keystroke")
corrected.type("x", now: t0)
corrected.type("", now: t0)
corrected.type("a", now: t0)
let live = corrected.live(now: t0.addingTimeInterval(6))!
assert(abs(live.wpm - 2) < 0.001 && abs(live.accuracy - 0.5) < 0.001, "live \(live)") // 1 correct char in 0.1 min; 1 of 2 keystrokes wrong
let done = corrected.type("añ", now: t0.addingTimeInterval(1))!
assert(abs(done.accuracy - 2.0 / 3) < 0.001 && corrected.correct == 2 && corrected.errors == 1, "corrected \(done) \(corrected.errors)")

// A dead key (´ then á at the same length) is re-scored, and the round waits for the composed letter.
var accent = Round(quotes: [Quote(text: "á")])
assert(accent.type("´", now: t0) == nil, "pending accent does not finish")
let composed = accent.type("á", now: t0.addingTimeInterval(1))
assert(composed?.accuracy == 1 && accent.errors == 0, "composed \(String(describing: composed)) errors \(accent.errors)")

// NFD and NFC spellings compare equal, one character each.
var nfd = Round(quotes: [Quote(text: "man\u{0303}ana")])
nfd.type("mañana", now: t0)
assert(nfd.correct == 6 && nfd.errors == 0, "nfd \(nfd.correct) \(nfd.errors)")
assert(wrapLines(nfd.target, width: 10) == [0..<6])

// The source follows the quote under the cursor.
var sourced = Round(quotes: Array(Collection.stoic.es.prefix(2)))
assert(sourced.source == sourced.quotes[0].source, "first source")
sourced.type(String(sourced.target.prefix(sourced.quotes[0].text.count + 1)), now: t0)
assert(sourced.source == sourced.quotes[1].source, "second source")

// pickQuotes takes whole quotes until the joined text is long enough.
let four = ["aaaa", "bbbb", "cccc"].map { Quote(text: $0) }
let picked = pickQuotes(from: four, chars: 6, maxChars: .max).map(\.text)
assert(picked.joined(separator: " ").count == 9, "picked \(picked)") // two quotes and a space
// maxChars skips quotes that would overflow it, but never leaves the round empty.
let long = String(repeating: "x", count: 20)
// Quotes that fit come first: the oversize one is used only when nothing else fits.
for _ in 0..<50 {
    let capped = pickQuotes(from: four + [Quote(text: long)], chars: 12, maxChars: 14).map(\.text)
    assert(capped.sorted() == ["aaaa", "bbbb", "cccc"], "capped \(capped)")
}
assert(pickQuotes(from: [Quote(text: long)], chars: 12, maxChars: 14).map(\.text) == [long], "only long")

// Built-in collections: >=30 distinct quotes per language (25...300 chars, normalized, no wide chars),
// with a non-empty source on every collection except General, and rounds within 30...90s at 40 wpm.
struct RawCollection: Encodable { var name: String; var quotes: [Quote] }
assert(Set(Collection.builtIn.map(\.id)).count == Collection.builtIn.count && Collection.builtIn.allSatisfy { !$0.id.hasPrefix("file:") })
for c in Collection.builtIn {
    let minCount = c.id == "general" ? 100 : (c.id == "stoic" ? 40 : 30)
    assert(c.es.count == c.en.count, "\(c.id) es/en count mismatch (\(c.es.count) vs \(c.en.count))")
    for lang in [Lang.es, .en] {
        let quotes = c.quotes(lang)
        let texts = quotes.map(\.text)
        let reparsed = try! Collection.parse(JSONEncoder().encode(RawCollection(name: c.name, quotes: quotes)), id: c.id)
        assert(quotes.count >= minCount && Set(texts).count == quotes.count, "\(c.id) \(lang) count/unique")
        assert(reparsed.skipped == 0 && reparsed.collection.es == quotes, "\(c.id) \(lang) normalized/maxChars/noWide")
        assert(quotes.allSatisfy { $0.text.count >= 25 }, "\(c.id) \(lang) min 25 chars")
        if c.id != "general" {
            assert(quotes.allSatisfy { !($0.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }, "\(c.id) \(lang) source")
        }
        for _ in 0..<20 {
            let round = pickQuotes(from: quotes, chars: charsFor(wpm: 40, seconds: .random(in: 30...60)), maxChars: Collection.maxChars)
            let len = round.map(\.text).joined(separator: " ").count
            assert((charsFor(wpm: 40, seconds: 30)...Collection.maxChars).contains(len), "\(c.id) \(lang) round \(len)")
        }
    }
}

// wrapLines breaks after spaces, keeps trailing spaces, and hard-breaks words longer than a line.
assert(wrapLines("aaa bbb ccc", width: 7) == [0..<8, 8..<11])
assert(wrapLines("aaaaaaaaaa", width: 4) == [0..<4, 4..<8, 8..<10])
assert(wrapLines("ab", width: 7) == [0..<2])

// markRuns: one run per stretch of characters drawn alike, limited to the line's range.
let runs = markRuns(Array("abcdefgh"), typed: Array("abXdY"), in: 1..<8)
assert(runs.map(\.range) == [1..<2, 2..<3, 3..<4, 4..<5, 5..<6, 6..<8] && runs.map(\.mark) == [.correct, .wrong, .correct, .wrong, .cursor, .pending], "\(runs)")
assert(markRuns(Array("abcd"), typed: Array("abcd"), in: 0..<4).map(\.mark) == [.correct], "finished round: no cursor")
assert(markRuns(Array("abcd"), typed: [], in: 2..<4).map(\.mark) == [.pending], "untouched line")
assert(markRuns(Array("abcd"), typed: Array("xy"), in: 0..<4).map(\.range) == [0..<2, 2..<3, 3..<4], "errors merge")

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

// Session saves the finished round with its language.
let historyURL = tempDir().appendingPathComponent("history.json")
let session = Session(history: History(url: historyURL), folder: tempDir(), defaults: freshDefaults())
session.practice("añ")
session.type("a", now: t0)
session.type("añ", now: t0.addingTimeInterval(1))
assert(session.result?.wpm == 24 && session.result?.lang == session.lang, "result \(String(describing: session.result))")
assert(History(url: historyURL).rounds.map(\.wpm) == [24], "saved")
assert(!session.isRecord, "no record on the very first round")

// A round is a record only when it beats every saved round (the first one was 24 wpm).
func finishedRound(seconds: Double) -> Session {
    let s = Session(history: History(url: historyURL), folder: tempDir(), defaults: freshDefaults())
    s.practice("ab")
    s.type("a", now: t0)
    s.type("ab", now: t0.addingTimeInterval(seconds))
    return s
}
assert(finishedRound(seconds: 0.5).isRecord, "48 wpm beats 24")
assert(!finishedRound(seconds: 2).isRecord, "12 wpm is below the best")

// A history file corrupt at launch is read-only: add() throws (so the note shows) and the file stays as it is.
let dir = tempDir()
let corrupt = dir.appendingPathComponent("history.json")
try! Data("not json".utf8).write(to: corrupt)
var history = History(url: corrupt)
var corruptThrew = false
do { try history.add(RoundResult(date: Date(), lang: .es, wpm: 50, accuracy: 1, seconds: 40)) } catch { corruptThrew = true }
assert(corruptThrew && (try! String(contentsOf: corrupt, encoding: .utf8)) == "not json"
    && (try! FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["history.json"], "corrupt history kept in place")

// A history that cannot be read is read-only: add() throws (so the note shows) and touches nothing.
let unreadable = tempDir()
var readOnly = History(url: unreadable)
var threw = false
do { try readOnly.add(RoundResult(date: Date(), lang: .es, wpm: 50, accuracy: 1, seconds: 40)) } catch { threw = true }
assert(threw && readOnly.rounds.count == 1, "read-only history throws")
assert(try! FileManager.default.contentsOfDirectory(atPath: unreadable.path).isEmpty, "directory untouched")
// A file without read permission is kept, not replaced by the new round.
let lockedURL = tempDir().appendingPathComponent("history.json")
var lockedSetup = History(url: lockedURL)
try! lockedSetup.add(RoundResult(date: Date(), lang: .es, wpm: 30, accuracy: 1, seconds: 40))
try! FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: lockedURL.path)
var locked = History(url: lockedURL)
threw = false
do { try locked.add(RoundResult(date: Date(), lang: .es, wpm: 50, accuracy: 1, seconds: 40)) } catch { threw = true }
try! FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedURL.path)
assert(threw && History(url: lockedURL).rounds.map(\.wpm) == [30], "unreadable history kept")

// Two app instances on one file keep each other's rounds.
let sharedURL = tempDir().appendingPathComponent("history.json")
var first = History(url: sharedURL)
var secondInstance = History(url: sharedURL)
try! first.add(RoundResult(date: Date(), lang: .es, wpm: 30, accuracy: 1, seconds: 40))
try! secondInstance.add(RoundResult(date: Date(), lang: .es, wpm: 40, accuracy: 1, seconds: 40))
assert(History(url: sharedURL).rounds.count == 2, "shared \(History(url: sharedURL).rounds.count)")

// recentWPM: the mean of the last 10 rounds; nil with no history.
var recent = History(url: tempDir().appendingPathComponent("history.json"))
assert(recent.recentWPM == nil)
try! recent.add(RoundResult(date: Date(), lang: .es, wpm: 0, accuracy: 1, seconds: 40))
for _ in 0..<10 { try! recent.add(RoundResult(date: Date(), lang: .es, wpm: 50, accuracy: 1, seconds: 40)) }
assert(recent.recentWPM == 50, "recentWPM \(String(describing: recent.recentWPM))")


// recentWPMs: the last 20 saved rounds, oldest first, ending with the round just finished.
let chartURL = tempDir().appendingPathComponent("history.json")
var chartHistory = History(url: chartURL)
for i in 0..<25 { try! chartHistory.add(RoundResult(date: Date(), lang: .es, wpm: Double(i), accuracy: 1, seconds: 30)) }
let chart = Session(history: chartHistory, folder: tempDir(), defaults: freshDefaults())
chart.practice("ab")
chart.type("a", now: t0)
chart.type("ab", now: t0.addingTimeInterval(6))
assert(chart.recentWPMs.count == 20 && chart.recentWPMs.first == 6 && chart.recentWPMs.last == chart.result?.wpm, "chart \(chart.recentWPMs)")

// toggleLanguage flips the language and starts a fresh round.
let toggled = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: tempDir(), defaults: freshDefaults())
let langBefore = toggled.lang, roundBefore = toggled.roundNumber
toggled.type("x", now: t0)
toggled.toggleLanguage()
assert(toggled.lang == langBefore.toggled && toggled.roundNumber == roundBefore + 1 && toggled.round.typed.isEmpty, "toggle")
toggled.toggleLanguage()

// A round never passes 90 seconds at the recent WPM.
var slowHistory = History(url: tempDir().appendingPathComponent("history.json"))
try! slowHistory.add(RoundResult(date: Date(), lang: .es, wpm: 20, accuracy: 1, seconds: 40))
let slow = Session(history: slowHistory, folder: tempDir(), defaults: freshDefaults())
for c in Collection.builtIn {
    slow.choose(c)
    for _ in 0..<20 {
        slow.newRound()
        assert(slow.round.target.count <= charsFor(wpm: 20, seconds: 90), "round \(c.id) \(slow.round.target.count)")
    }
}

// Picker: every letter filters (accent- and case-insensitive), moving is clamped, ⏎ chooses.
let picker = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: tempDir(), defaults: freshDefaults())
picker.choose(.general)
picker.openPicker()
assert(picker.picking && picker.selection == 0)
picker.movePicker(-1)
assert(picker.selection == 0, "stops at the top")
for _ in 0..<(Collection.builtIn.count + 1) { picker.movePicker(1) }
assert(picker.selection == Collection.builtIn.count - 1, "stops at the bottom")
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
assert(!picker.picking && picker.collection.id == "stoic" && picker.round.quotes.allSatisfy { $0.source != nil }, "chose stoic")
picker.openPicker()
assert(picker.selection == 1, "opens on the current collection")
picker.deleteInPicker()
assert(picker.selection == 1, "delete on an empty filter keeps the selection")
picker.typeInPicker("\u{F700}")
assert(picker.filter.isEmpty && picker.selection == 1, "arrow characters are ignored")
picker.typeInPicker("node.js")
assert(picker.filter == "node.js", "the filter keeps punctuation")
for _ in 0..<7 { picker.deleteInPicker() }
picker.typeInPicker("GENERAL")
assert(picker.matches.map(\.id) == ["general"])
picker.closePicker()
assert(!picker.picking && picker.collection.id == "stoic", "esc keeps the collection")

// User collections: a JSON file with a name and quotes, used whatever the language.
let valid = Data(#"{"name": " Programación ", "quotes": [{"text": " Talk is cheap. ", "source": "Linus Torvalds"}, {"text": "Sin fuente."}]}"#.utf8)
let parsed = try! Collection.parse(valid, id: "file:p.json")
assert(parsed.collection.name == "Programación" && parsed.skipped == 0, "parsed \(parsed)")
assert(parsed.collection.es == [Quote(text: "Talk is cheap.", source: "Linus Torvalds"), Quote(text: "Sin fuente.")], "quotes \(parsed.collection.es)")
assert(parsed.collection.es == parsed.collection.en)
let tooLong = String(repeating: "x", count: Collection.maxChars + 1)
let trimmed = try! Collection.parse(Data(#"{"name": "A", "quotes": [{"text": "ok"}, {"text": "  "}, {"text": "\#(tooLong)"}]}"#.utf8), id: "a")
assert(Collection.maxChars == 300 && trimmed.collection.es.map(\.text) == ["ok"] && trimmed.skipped == 2, "skipped \(trimmed.skipped)")
// Whitespace runs become one space; emoji and wide characters are skipped.
let wide = try! Collection.parse(Data(#"{"name": "W", "quotes": [{"text": "a\n\tb\u00a0 c"}, {"text": "hola 😀"}, {"text": "日本"}, {"text": "한국"}, {"text": "カナ"}, {"text": "ＡＢ"}, {"text": "te \u2764\ufe0f"}, {"text": "ojo \u26a0\ufe0f"}]}"#.utf8), id: "w")
assert(wide.collection.es.map(\.text) == ["a b c"] && wide.skipped == 7, "wide \(wide.collection.es) \(wide.skipped)")

// load: broken files become problems, the valid one still loads.
let folder = tempDir()
try! valid.write(to: folder.appendingPathComponent("prog.json"))
try! Data("not json".utf8).write(to: folder.appendingPathComponent("bad.json"))
try! Data(#"{"name": "Sin frases"}"#.utf8).write(to: folder.appendingPathComponent("empty.json"))
try! Data("ignored".utf8).write(to: folder.appendingPathComponent("notes.txt"))
let loaded = Collection.load(from: folder)
assert(loaded.collections.map(\.id) == ["file:prog.json"], "loaded \(loaded.collections.map(\.id))")
assert(loaded.problems.count == 2 && loaded.problems.allSatisfy { $0.hasPrefix("bad.json") || $0.hasPrefix("empty.json") }, "problems \(loaded.problems)")
// Files over 1 MB and things that are not regular files are reported, not read.
let odd = tempDir()
try! Data(count: 1_000_001).write(to: odd.appendingPathComponent("big.json"))
try! FileManager.default.createDirectory(at: odd.appendingPathComponent("dir.json"), withIntermediateDirectories: true)
let oddLoaded = Collection.load(from: odd)
assert(oddLoaded.collections.isEmpty && oddLoaded.problems == ["big.json: más de 1 MB", "dir.json: no es un archivo normal"], "odd \(oddLoaded.problems)")

// A Session lists file collections after the built-ins and practices with them.
let builtInIds = Collection.builtIn.map(\.id)
let userDefaults = freshDefaults()
let user = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: folder, defaults: userDefaults)
assert(user.collections.map(\.id) == builtInIds + ["file:prog.json"] && user.problems.count == 2, "collections \(user.collections.map(\.id))")
user.choose(user.collections.last!)
assert(user.round.quotes.allSatisfy { parsed.collection.es.contains($0) } && !user.round.quotes.isEmpty, "file quotes \(user.round.quotes)")

// Favorites come first; ⌃f keeps the same collection selected as it moves.
user.openPicker()
assert(user.selection == builtInIds.count)
user.toggleFavoritePicked()
assert(user.matches.map(\.id) == ["file:prog.json"] + builtInIds && user.selection == 0, "favorite first \(user.matches.map(\.id))")
user.toggleFavoritePicked()
assert(user.matches.map(\.id) == builtInIds + ["file:prog.json"] && user.selection == builtInIds.count, "unfavorited")
user.closePicker()

// A chosen file collection whose file is deleted falls back to General.
try! FileManager.default.removeItem(at: folder.appendingPathComponent("prog.json"))
user.reloadCollections()
assert(user.collection.id == "general" && user.collections.count == builtInIds.count, "fallback \(user.collection.id)")
// The fallback lives in memory only: the saved collection comes back with its file, also after a relaunch.
try! valid.write(to: folder.appendingPathComponent("prog.json"))
user.reloadCollections()
assert(user.collection.id == "file:prog.json", "back \(user.collection.id)")
let relaunched = Session(history: History(url: tempDir().appendingPathComponent("history.json")), folder: folder, defaults: userDefaults)
assert(relaunched.collection.id == "file:prog.json", "relaunch \(relaunched.collection.id)")

// Clicking a picker row chooses that collection and closes the picker, like moving to it and pressing return.
let clickDir = tempDir()
let clicked = Session(history: History(url: clickDir.appendingPathComponent("history.json")), folder: clickDir, defaults: freshDefaults())
clicked.openPicker()
let second = clicked.matches[1]
clicked.chooseMatch(at: 1)
assert(clicked.collection == second && !clicked.picking, "clicked \(clicked.collection.id)")

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
// ⌘+letter belongs to apps and ⌥+letter types accents.
assert(HotKey(event: keyEvent("c", code: 8, .command)) == nil && HotKey(event: keyEvent("C", code: 8, [.command, .shift])) == nil, "⌘C")
assert(HotKey(event: keyEvent("e", code: 14, .option)) == nil, "⌥E")
// ⌥ plus a symbol key types that symbol (⌥+ is ] on a Spanish keyboard), and a dead key types one once composed.
assert(HotKey(event: keyEvent("+", code: 30, .option)) == nil, "⌥+")
let deadKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil,
                               characters: "æ", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 39)!
assert(HotKey(event: deadKey) == nil, "⌥ dead key")
// Keys that type nothing still work with ⌥ alone, recorded and saved.
let optionArrow = HotKey(event: keyEvent("\u{F702}", code: 123, .option))
assert(optionArrow?.label == "⌥←", "⌥← \(String(describing: optionArrow))")
UserDefaults.standard.set(try! JSONEncoder().encode(optionArrow), forKey: "hotKey")
assert(HotKey.saved == optionArrow, "saved ⌥← kept")
UserDefaults.standard.set(try! JSONEncoder().encode(HotKey(code: 30, mods: UInt32(optionKey), key: "+")), forKey: "hotKey")
assert(HotKey.saved == .standard, "saved ⌥+ refused")
// A saved shortcut without ⌘, ⌥ or ⌃ falls back to the default.
UserDefaults.standard.set(try! JSONEncoder().encode(HotKey(code: 17, mods: UInt32(shiftKey), key: "T")), forKey: "hotKey")
assert(HotKey.saved == .standard, "saved fallback")
UserDefaults.standard.set(try! JSONEncoder().encode(HotKey(code: 8, mods: UInt32(cmdKey), key: "C")), forKey: "hotKey")
assert(HotKey.saved == .standard, "saved ⌘C refused")
UserDefaults.standard.set(try! JSONEncoder().encode(HotKey(code: 14, mods: UInt32(optionKey), key: "E")), forKey: "hotKey")
assert(HotKey.saved == .standard, "saved ⌥E refused")
UserDefaults.standard.removeObject(forKey: "hotKey")

// A file that turns corrupt while running is kept, not overwritten with the rounds in memory.
let laterURL = tempDir().appendingPathComponent("history.json")
var later = History(url: laterURL)
try! later.add(RoundResult(date: Date(), lang: .es, wpm: 30, accuracy: 1, seconds: 30))
try! Data("[ broken".utf8).write(to: laterURL)
var laterThrew = false
do { try later.add(RoundResult(date: Date(), lang: .es, wpm: 40, accuracy: 1, seconds: 30)) } catch { laterThrew = true }
assert(laterThrew && (try! String(contentsOf: laterURL, encoding: .utf8)) == "[ broken", "later corrupt history kept")

// A valid file over 1 MB is refused at parse, so import never copies what load would skip.
let hugeQuotes = Array(repeating: #"{"text": "\#(String(repeating: "a", count: 250))"}"#, count: 4500).joined(separator: ",")
let huge = Data(#"{"name": "Huge", "quotes": [\#(hugeQuotes)]}"#.utf8)
assert(huge.count > 1_000_000 && (try? Collection.parse(huge, id: "file:huge.json")) == nil, "parse refuses over 1 MB")

// Default support paths live under ~/Library/Application Support/AiberTyper, and migrate/merge from AitorTyper.
assert(Collection.folder.path.hasSuffix("/AiberTyper/Colecciones"), "folder \(Collection.folder.path)")
assert(History.defaultURL.path.hasSuffix("/AiberTyper/history.json"), "history \(History.defaultURL.path)")
let support = tempDir()
let legacyHistoryURL = support.appendingPathComponent("AitorTyper/history.json")
let aiberHistoryURL = support.appendingPathComponent("AiberTyper/history.json")
var legacyHistory = History(url: legacyHistoryURL)
try! legacyHistory.add(RoundResult(date: t0, lang: .es, wpm: 55, accuracy: 1, seconds: 30))
try! legacyHistory.add(RoundResult(date: t0.addingTimeInterval(10), lang: .es, wpm: 62, accuracy: 1, seconds: 30))
var aiberHistory = History(url: aiberHistoryURL)
try! aiberHistory.add(RoundResult(date: t0.addingTimeInterval(20), lang: .es, wpm: 70, accuracy: 1, seconds: 30))
let mergedHistory = History(url: aiberHistoryURL)
assert(mergedHistory.rounds.map(\.wpm) == [55, 62, 70], "merged \(mergedHistory.rounds.map(\.wpm))")
assert(History(url: legacyHistoryURL).rounds.count == 2, "legacy history kept intact")
let legacyCols = support.appendingPathComponent("AitorTyper/Colecciones")
try! FileManager.default.createDirectory(at: legacyCols, withIntermediateDirectories: true)
try! valid.write(to: legacyCols.appendingPathComponent("prog.json"))
let aiberCols = support.appendingPathComponent("AiberTyper/Colecciones")
assert(Collection.load(from: aiberCols).collections.map(\.id) == ["file:prog.json"], "migrated collection")
// The copy runs once: a collection deleted by hand stays deleted.
try! FileManager.default.removeItem(at: aiberCols.appendingPathComponent("prog.json"))
assert(Collection.load(from: aiberCols).collections.isEmpty, "deleted collection came back")

// Settings saved under the old bundle id are copied once, without overwriting newer ones.
let oldSuite = "aibertyper.selfcheck.old.\(UUID().uuidString)", newSuite = "aibertyper.selfcheck.new.\(UUID().uuidString)"
let oldDefaults = UserDefaults(suiteName: oldSuite)!, newDefaults = UserDefaults(suiteName: newSuite)!
oldDefaults.set("en", forKey: "lang")
oldDefaults.set("stoic", forKey: "pack")
oldDefaults.set(["cinema"], forKey: "favorites")
oldDefaults.set(Data("k".utf8), forKey: "hotKey")
oldDefaults.set(true, forKey: "hideImportHelp")
newDefaults.set(["books"], forKey: "favorites")
migrateDefaults(from: oldDefaults, to: newDefaults)
assert(newDefaults.string(forKey: "lang") == "en" && newDefaults.string(forKey: "pack") == "stoic"
    && newDefaults.data(forKey: "hotKey") == Data("k".utf8) && newDefaults.bool(forKey: "hideImportHelp"), "defaults copied")
assert(newDefaults.stringArray(forKey: "favorites") == ["books"], "newer favorites kept")
for suite in [oldSuite, newSuite] { UserDefaults.standard.removePersistentDomain(forName: suite) }

// install: a valid file is copied into the folder (created if missing) and loads under the returned id.
let inbox = tempDir()
let shelf = tempDir().appendingPathComponent("Colecciones")
try! valid.write(to: inbox.appendingPathComponent("prog.json"))
let installedId = try! Collection.install(inbox.appendingPathComponent("prog.json"), into: shelf)
assert(installedId == "file:prog.json" && Collection.load(from: shelf).collections.map(\.id) == [installedId], "installed \(installedId)")
// A broken file is refused with the same wording load uses, and never lands in the folder.
try! Data("not json".utf8).write(to: inbox.appendingPathComponent("bad.json"))
var installError = ""
do { _ = try Collection.install(inbox.appendingPathComponent("bad.json"), into: shelf) } catch { installError = error.localizedDescription }
assert(installError == "JSON no válido" && !FileManager.default.fileExists(atPath: shelf.appendingPathComponent("bad.json").path), "refused \(installError)")
assert(loaded.problems.contains("bad.json: JSON no válido"), "load wording \(loaded.problems)")
// Re-importing a file from the folder itself keeps it instead of trashing its own source.
let again = try! Collection.install(shelf.appendingPathComponent("prog.json"), into: shelf)
assert(again == installedId && (try! Data(contentsOf: shelf.appendingPathComponent("prog.json"))) == valid, "same file kept")
// Replacing a different file moves the old one to the user's real Trash, so it is not exercised here.

// Panel keys: the typing view and the picker each map keys their own way.
func panelKey(_ chars: String, _ code: Int, _ flags: NSEvent.ModifierFlags = [], picking: Bool = false) -> PanelKey {
    PanelKey(event: keyEvent(chars, code: UInt16(code), flags), picking: picking)
}
assert(panelKey("\u{1b}", kVK_Escape) == .hide && panelKey("\t", kVK_Tab) == .toggleLanguage && panelKey("\t", kVK_Tab, .shift) == .openPicker)
assert(panelKey("\r", kVK_Return) == .newRound && panelKey("\u{3}", kVK_ANSI_KeypadEnter) == .newRound)
// Keys that would move the hidden field's caret are swallowed; everything else types.
for code in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete] {
    assert(panelKey("\u{F702}", code) == .ignore, "swallowed \(code)")
}
assert(panelKey("j", kVK_ANSI_J) == .pass && panelKey("a", kVK_ANSI_A) == .pass && panelKey("\u{7f}", kVK_Delete) == .pass, "typing keys pass")
// In the picker plain j/k filter; ⌃j/⌃k and the arrows move.
assert(panelKey("j", kVK_ANSI_J, picking: true) == .filter("j") && panelKey("K", kVK_ANSI_K, .shift, picking: true) == .filter("K"), "plain j/k filter")
assert(panelKey("j", kVK_ANSI_J, .control, picking: true) == .move(1) && panelKey("k", kVK_ANSI_K, .control, picking: true) == .move(-1), "⌃j/⌃k move")
assert(panelKey("\u{F701}", kVK_DownArrow, picking: true) == .move(1) && panelKey("\u{F700}", kVK_UpArrow, picking: true) == .move(-1), "arrows move")
assert(panelKey("f", kVK_ANSI_F, .control, picking: true) == .favorite && panelKey("i", kVK_ANSI_I, .control, picking: true) == .importCollections)
assert(panelKey("\u{1b}", kVK_Escape, picking: true) == .closePicker && panelKey("\t", kVK_Tab, picking: true) == .closePicker
    && panelKey("\t", kVK_Tab, .shift, picking: true) == .closePicker, "esc and tab close the picker")
assert(panelKey("\r", kVK_Return, picking: true) == .choose && panelKey("\u{7f}", kVK_Delete, picking: true) == .delete)
assert(panelKey("a", kVK_ANSI_A, .command, picking: true) == .ignore && panelKey("x", kVK_ANSI_X, .control, picking: true) == .ignore, "⌘ and other ⌃ keys do nothing")

for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
print("self-check OK")
