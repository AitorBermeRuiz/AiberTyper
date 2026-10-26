// Writes the data the Windows port shares with the Mac app into src/windows/shared/, using the Swift code as the reference:
// the built-in collections, the Unicode tables Collection.parse relies on, and test vectors the Go tests replay.
// Run it through src/mac/export-shared.sh; CI fails when the committed files are out of date.
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func write<T: Encodable>(_ value: T, _ name: String) {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try! e.encode(value).write(to: out.appendingPathComponent(name))
}

// Built-in collections.
struct SharedCollection: Encodable { var id: String; var name: String; var es: [Quote]; var en: [Quote] }
write(Collection.builtIn.map { SharedCollection(id: $0.id, name: $0.name, es: $0.es, en: $0.en) }, "collections.json")

// Scalar ranges for the rules Go has no exact equivalent for.
func ranges(_ test: (Unicode.Scalar) -> Bool) -> [[UInt32]] {
    var result: [[UInt32]] = []
    for value in UInt32(0)...0x10FFFF {
        guard let scalar = Unicode.Scalar(value), test(scalar) else { continue }
        if let last = result.last, last[1] == value - 1 { result[result.count - 1][1] = value } else { result.append([value, value]) }
    }
    return result
}
struct UnicodeTables: Encodable { var wide: [[UInt32]]; var whitespace: [[UInt32]] }
write(UnicodeTables(wide: ranges(Collection.isWide), whitespace: ranges { Character($0).isWhitespace }), "unicode.json")

// Test vectors: inputs and what the Swift code returns for them.
struct Pair: Encodable { var lower: Int; var upper: Int; init(_ r: Range<Int>) { lower = r.lowerBound; upper = r.upperBound } }
struct CharsCase: Encodable { var wpm: Double; var seconds: Double; var out: Int }
struct WrapCase: Encodable { var text: String; var width: Int; var out: [Pair] }
struct WindowCase: Encodable { var lines: [Pair]; var cursor: Int; var before: Int?; var focus: Pair; var after: Int? }
struct Run: Encodable { var range: Pair; var mark: String }
struct RunsCase: Encodable { var target: String; var typed: String; var range: Pair; var out: [Run] }
struct Score: Encodable { var wpm: Double; var accuracy: Double; var seconds: Double? }
struct Step: Encodable {
    var text: String; var t: Double
    var result: Score?; var typed: String; var errors: Int; var correct: Int; var source: String?; var live: Score?
}
struct RoundCase: Encodable { var name: String; var quotes: [Quote]; var steps: [Step] }
struct ParseCase: Encodable { var json: String; var name: String?; var quotes: [Quote]?; var skipped: Int?; var error: String? }
struct ContainsCase: Encodable { var hay: String; var needle: String; var out: Bool }
struct Vectors: Encodable {
    var maxChars: Int
    var charsFor: [CharsCase]; var wrapLines: [WrapCase]; var lineWindow: [WindowCase]; var markRuns: [RunsCase]
    var rounds: [RoundCase]; var parse: [ParseCase]; var contains: [ContainsCase]
}

let stoic = Collection.stoic.es, general = Collection.general.en
let charsCases = [(40.0, 90.0), (40, 30), (20, 90), (73.5, 47.2), (120, 60)].map { CharsCase(wpm: $0, seconds: $1, out: charsFor(wpm: $0, seconds: $1)) }

var wrapInputs: [(String, Int)] = [("aaa bbb ccc", 7), ("aaaaaaaaaa", 4), ("ab", 7), ("", 5), ("a  b   c", 2), ("uno dos", 3)]
for width in [10, 37, 41, 50] {
    wrapInputs.append((stoic.prefix(6).map(\.text).joined(separator: " "), width))
    wrapInputs.append((general.prefix(4).map(\.text).joined(separator: " "), width))
}
let wrapCases = wrapInputs.map { WrapCase(text: $0, width: $1, out: wrapLines($0, width: $1).map(Pair.init)) }

let six = (0..<6).map { $0 * 10..<($0 + 1) * 10 }
var windowCases: [WindowCase] = []
for (lines, cursors) in [(six, [0, 9, 10, 25, 35, 51, 60]), ([0..<5, 5..<9], [0, 6, 9]), ([], [0]), ([0..<4], [0, 4])] {
    for cursor in cursors {
        let w = lineWindow(lines, cursor: cursor)
        windowCases.append(WindowCase(lines: lines.map(Pair.init), cursor: cursor, before: w.before, focus: Pair(w.focus), after: w.after))
    }
}

let runsInputs: [(String, String, Range<Int>)] = [
    ("abcdefgh", "abXdY", 1..<8), ("abcd", "abcd", 0..<4), ("abcd", "", 2..<4), ("abcd", "xy", 0..<4), ("añ é", "añx", 0..<4),
]
let runsCases = runsInputs.map { target, typed, range in
    RunsCase(target: target, typed: typed, range: Pair(range), out: markRuns(Array(target), typed: Array(typed), in: range).map {
        Run(range: Pair($0.range), mark: "\($0.mark)")
    })
}

/// Types `steps` (field text, seconds from the start) into a fresh round, recording what Round reports after each.
func roundCase(_ name: String, _ quotes: [Quote], _ steps: [(String, Double)]) -> RoundCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var round = Round(quotes: quotes)
    return RoundCase(name: name, quotes: quotes, steps: steps.map { text, t in
        let now = t0.addingTimeInterval(t)
        let result = round.type(text, now: now)
        return Step(text: text, t: t, result: result.map { Score(wpm: $0.wpm, accuracy: $0.accuracy, seconds: $0.seconds) },
                    typed: round.typed, errors: round.errors, correct: round.correct, source: round.source,
                    live: round.live(now: now).map { Score(wpm: $0.wpm, accuracy: $0.accuracy) })
    })
}

/// A typist with a fixed seed: mostly right, sometimes wrong, sometimes fixing the mistake with backspace.
func simulated(_ quotes: [Quote], seed: UInt64) -> [(String, Double)] {
    var state = seed
    func next() -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int(state >> 33) }
    let target = Array(quotes.map(\.text).joined(separator: " "))
    var typed: [Character] = [], steps: [(String, Double)] = [], t = 0.0
    while typed.count < target.count {
        t += Double(next() % 400 + 80) / 1000
        if next() % 12 == 0 {
            typed.append("#")
            steps.append((String(typed), t))
            if next() % 2 == 0 { typed.removeLast(); t += 0.2; steps.append((String(typed), t)) }
        } else {
            typed.append(target[typed.count])
            steps.append((String(typed), t))
        }
    }
    return steps
}

let rounds = [
    roundCase("score", [Quote(text: "hola mundo")], [("hola mund", 0), ("hola mundx", 6), ("hola mundo", 7)]),
    roundCase("corrected", [Quote(text: "añ")], [("x", 0), ("", 0), ("a", 0), ("añ", 1)]),
    roundCase("dead key", [Quote(text: "á")], [("´", 0), ("á", 1)]),
    roundCase("dead key wrong", [Quote(text: "ab")], [("a", 0), ("´", 1), ("é", 2), ("ab", 3)]),
    roundCase("overflow", [Quote(text: "abc")], [("abcdef", 2)]),
    roundCase("sources", Array(stoic.prefix(3)), [(String(stoic[0].text.prefix(10)), 1), (stoic[0].text + " ", 5), (stoic[0].text + " " + stoic[1].text + " x", 9)]),
    roundCase("simulated stoic", Array(stoic.suffix(2)), simulated(Array(stoic.suffix(2)), seed: 7)),
    roundCase("simulated general", Array(general.prefix(2)), simulated(Array(general.prefix(2)), seed: 42)),
]

let tooLong = String(repeating: "x", count: Collection.maxChars + 1)
let parseInputs = [
    #"{"name": " Programación ", "quotes": [{"text": " Talk is cheap. ", "source": "Linus Torvalds"}, {"text": "Sin fuente."}]}"#,
    #"{"name": "A", "quotes": [{"text": "ok"}, {"text": "  "}, {"text": "\#(tooLong)"}]}"#,
    #"{"name": "W", "quotes": [{"text": "a\n\tb  c"}, {"text": "hola 😀"}, {"text": "日本"}, {"text": "한국"}, {"text": "カナ"}, {"text": "ＡＢ"}, {"text": "te ❤️"}, {"text": "ojo ⚠️"}, {"text": "te ❤ sí"}, {"text": "fin de　línea"}]}"#,
    #"{"name": "S", "quotes": [{"text": "con fuente nula", "source": null}], "extra": 1}"#,
    #"{"name": "  ", "quotes": [{"text": "a"}]}"#,
    #"{"name": "Vacía", "quotes": []}"#,
    #"{"name": "Larga", "quotes": [{"text": "\#(tooLong)"}]}"#,
    #"{"quotes": [{"text": "sin nombre"}]}"#,
    #"{"name": "Sin frases"}"#,
    #"{"name": "Sin texto", "quotes": [{"source": "x"}]}"#,
    #"{"NAME": "Mayúsculas", "QUOTES": [{"TEXT": "claves"}]}"#,
    #"{"name": 5, "quotes": []}"#,
    #"["no", "es", "objeto"]"#,
    "not json",
    "",
]
let parseCases = parseInputs.map { json -> ParseCase in
    do {
        let p = try Collection.parse(Data(json.utf8), id: "file:x.json")
        return ParseCase(json: json, name: p.collection.name, quotes: p.collection.es, skipped: p.skipped)
    } catch {
        return ParseCase(json: json, error: error.localizedDescription)
    }
}

let containsInputs = [
    ("Estoicismo", "est"), ("Estoicismo", "EST"), ("Programación", "programacion"), ("Programacion", "ación"), ("El arte de la guerra", "ARTE DE"),
    ("Libros de culto", "x"), ("Cine", ""), ("Pingüino", "pinguino"), ("Ñandú", "nandu"), ("niño", "NIÑO"), ("Çava", "ca"), ("node.js", "node.js"),
    ("Ærø", "aero"), ("straße", "STRASSE"), ("İstanbul", "istanbul"), ("Œuvre", "oeuvre"), ("Crème brûlée", "creme brulee"), ("Zoë", "zoe"),
]
let containsCases = containsInputs.map { ContainsCase(hay: $0, needle: $1, out: $1.isEmpty || $0.localizedStandardContains($1)) }

write(Vectors(maxChars: Collection.maxChars, charsFor: charsCases, wrapLines: wrapCases, lineWindow: windowCases, markRuns: runsCases,
              rounds: rounds, parse: parseCases, contains: containsCases), "vectors.json")
print("wrote \(out.path)")
