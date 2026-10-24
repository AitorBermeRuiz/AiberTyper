import Foundation

enum Lang: String, Codable {
    case es, en
    var toggled: Lang { self == .es ? .en : .es }
    var label: String { self == .es ? "Español" : "English" }
    var sentences: [String] { self == .es ? Texts.es : Texts.en }
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

/// Joins whole shuffled sentences until the text reaches `chars` characters.
func makeText<R: RandomNumberGenerator>(from sentences: [String], chars: Int, using rng: inout R) -> String {
    var pool = sentences.shuffled(using: &rng)
    var picked: [String] = []
    while picked.joined(separator: " ").count < chars, let next = pool.popLast() {
        picked.append(next)
    }
    return picked.joined(separator: " ")
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
        guard let data = try? Data(contentsOf: url) else { return } // no history yet
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
        rounds.append(round)
        guard writable else { return }
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
