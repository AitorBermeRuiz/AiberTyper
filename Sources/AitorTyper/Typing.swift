import Foundation

enum Lang: String, Codable {
    case es, en
    var toggled: Lang { self == .es ? .en : .es }
    var label: String { self == .es ? "Español" : "English" }
}

/// A sentence to type; `source` names the work it is quoted from.
struct Quote: Codable, Equatable {
    var text: String
    var source: String?
}

/// A set of sentences to practice with: built in, or loaded from a JSON file in `Collection.folder`.
struct Collection: Equatable {
    var id: String
    var name: String
    var es: [Quote]
    var en: [Quote]

    func quotes(_ lang: Lang) -> [Quote] { lang == .es ? es : en }

    static let general = Collection(id: "general", name: "General", es: Texts.es.map { Quote(text: $0) }, en: Texts.en.map { Quote(text: $0) })
    static let stoic = Collection(id: "stoic", name: "Estoicismo", es: Texts.stoicEs, en: Texts.stoicEn)
    static let programming = Collection(id: "programming", name: "Programación", es: Texts.programmingEs, en: Texts.programmingEn)
    static let artOfWar = Collection(id: "art-of-war", name: "El arte de la guerra", es: Texts.artOfWarEs, en: Texts.artOfWarEn)
    static let cinema = Collection(id: "cinema", name: "Cine", es: Texts.cinemaEs, en: Texts.cinemaEn)
    static let books = Collection(id: "books", name: "Libros de culto", es: Texts.booksEs, en: Texts.booksEn)
    static let builtIn = [general, stoic, programming, artOfWar, cinema, books]

    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AitorTyper/Colecciones")

    /// Longest sentence kept from a file: 90 seconds at 40 wpm.
    static let maxChars = charsFor(wpm: 40, seconds: 90)
    static let maxBytes = 1_000_000

    /// The JSON format users write: `{"name": "…", "quotes": [{"text": "…", "source": "…"}]}`.
    /// The sentences are used whatever language is selected.
    static func parse(_ data: Data, id: String) throws -> (collection: Collection, skipped: Int) {
        guard data.count <= maxBytes else { throw CollectionError("más de 1 MB") }
        struct File: Decodable { var name: String; var quotes: [Quote] }
        let file = try JSONDecoder().decode(File.self, from: data)
        let name = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CollectionError("falta \"name\"") }
        let quotes = file.quotes
            .map { Quote(text: $0.text.split(whereSeparator: \.isWhitespace).joined(separator: " "), source: $0.source) }
            .filter { !$0.text.isEmpty && $0.text.count <= maxChars && !$0.text.unicodeScalars.contains(where: isWide) }
        guard !quotes.isEmpty else { throw CollectionError("no tiene frases de hasta \(maxChars) caracteres") }
        return (Collection(id: id, name: name, es: quotes, en: quotes), file.quotes.count - quotes.count)
    }

    /// Emoji and CJK, kana, Hangul or fullwidth characters take two monospaced cells and break the manual wrap.
    // shortcut: a fixed list of ranges, not real glyph measurement; measure with text layout if other wide scripts show up.
    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        // U+FE0F (VS16) turns a text-default symbol such as ❤ into a two-cell emoji.
        scalar.properties.isEmojiPresentation || scalar.properties.isIdeographic || scalar.value == 0xFE0F
            || [0x1100...0x11FF, 0xAC00...0xD7AF, 0x3040...0x30FF, 0xFF00...0xFF60].contains { $0.contains(scalar.value) }
    }

    /// Every `*.json` in `folder`, by file name, plus one message per file that could not be used.
    static func load(from folder: URL = folder) -> (collections: [Collection], problems: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])) ?? []
        var collections: [Collection] = []
        var problems: [String] = []
        for url in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { problems.append("\(url.lastPathComponent): no es un archivo normal"); continue }
            guard (values?.fileSize ?? 0) <= maxBytes else { problems.append("\(url.lastPathComponent): más de 1 MB"); continue }
            do {
                let parsed = try parse(Data(contentsOf: url), id: "file:" + url.lastPathComponent)
                collections.append(parsed.collection)
                if parsed.skipped > 0 { problems.append("\(url.lastPathComponent): \(parsed.skipped) frases vacías, con caracteres anchos o de más de \(maxChars) caracteres") }
            } catch {
                problems.append("\(url.lastPathComponent): \(error is DecodingError ? "JSON no válido" : error.localizedDescription)")
            }
        }
        return (collections, problems)
    }
}

struct CollectionError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct RoundResult: Codable, Equatable {
    var date: Date
    var lang: Lang
    var wpm: Double
    var accuracy: Double
    var seconds: Double
}

/// Characters a typist at `wpm` covers in `seconds` (a "word" is 5 characters).
func charsFor(wpm: Double, seconds: Double) -> Int { Int(wpm * 5 * seconds / 60) }

/// Whole shuffled sentences whose space-joined text reaches `chars` characters without passing
/// `maxChars`. Sentences that fit come first; an oversize one is taken only when none fits,
/// so the round is never empty.
func pickSentences<R: RandomNumberGenerator>(from sentences: [Quote], chars: Int, maxChars: Int = .max, using rng: inout R) -> [Quote] {
    let shuffled = sentences.shuffled(using: &rng)
    var picked: [Quote] = []
    var length = -1 // no separator before the first sentence
    for next in shuffled.filter({ $0.text.count <= maxChars }) + shuffled.filter({ $0.text.count > maxChars }) where length < chars {
        guard picked.isEmpty || length + 1 + next.text.count <= maxChars else { continue }
        picked.append(next)
        length += 1 + next.text.count
    }
    return picked
}

/// Word-wraps `text` into lines of at most `width` characters. Each line keeps its trailing space,
/// so the ranges are contiguous and cover the whole text.
func wrapLines(_ text: String, width: Int) -> [Range<Int>] {
    let chars = Array(text)
    var lines: [Range<Int>] = []
    var start = 0
    while start < chars.count {
        if chars.count - start <= width {
            lines.append(start..<chars.count)
            break
        }
        // A space right after `width` characters may hang at the end of the line.
        let space = chars[start...(start + width)].lastIndex(of: " ").flatMap { $0 > start ? $0 : nil }
        let end = space.map { $0 + 1 } ?? start + width
        lines.append(start..<end)
        start = end
    }
    return lines
}

/// Line indices to draw around the cursor: up to `focus` sharp lines, plus one dimmed before and after.
func lineWindow(_ lines: [Range<Int>], cursor: Int, focus: Int = 3) -> (before: Int?, focus: Range<Int>, after: Int?) {
    guard !lines.isEmpty else { return (nil, 0..<0, nil) }
    let current = lines.lastIndex { $0.lowerBound <= cursor } ?? 0
    // Keep the line before the cursor in focus once you are past the first one.
    let first = max(0, min(current - 1, lines.count - focus))
    let end = min(first + focus, lines.count)
    return (first > 0 ? first - 1 : nil, first..<end, end < lines.count ? end : nil)
}

/// WPM counts only correct characters; accuracy counts every keystroke, including corrected mistakes.
func score(target: String, typed: String, seconds: Double, keystrokes: Int, errors: Int) -> (wpm: Double, accuracy: Double) {
    let correct = zip(target, typed).filter { $0 == $1 }.count
    let wpm = seconds > 0 ? Double(correct) / 5 / (seconds / 60) : 0
    let accuracy = keystrokes > 0 ? Double(keystrokes - errors) / Double(keystrokes) : 1
    return (wpm, accuracy)
}

struct History {
    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AitorTyper/history.json")

    let url: URL
    private(set) var rounds: [RoundResult] = []
    private var writable = true

    init(url: URL = History.defaultURL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return } // no history yet
        // Any other read error (permissions, a directory) makes it read-only, so the file is never replaced.
        guard let data = try? Data(contentsOf: url) else { writable = false; return }
        do {
            rounds = try Self.decoder.decode([RoundResult].self, from: data)
        } catch {
            // Keep the unreadable file instead of overwriting it on the next save.
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            writable = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
        }
    }

    var recentWPM: Double? {
        let recent = rounds.suffix(10)
        return recent.isEmpty ? nil : recent.map(\.wpm).reduce(0, +) / Double(recent.count)
    }

    mutating func add(_ round: RoundResult) throws {
        // Another running instance may have saved rounds since this one read the file.
        // A file that turned unreadable since then is kept: the history becomes read-only.
        if writable, FileManager.default.fileExists(atPath: url.path) {
            do { rounds = try Self.decoder.decode([RoundResult].self, from: Data(contentsOf: url)) } catch { writable = false }
        }
        rounds.append(round)
        guard writable else { throw CollectionError("no se pudo leer \(url.lastPathComponent), así que no se sobrescribe") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(rounds).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
