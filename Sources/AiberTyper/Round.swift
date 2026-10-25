import Foundation

/// One attempt at a text: what was typed, every keystroke and the live score. Knows nothing of history or settings.
struct Round {
    /// The quotes that make up `target`, in order.
    let quotes: [Quote]
    let target: String
    private(set) var typed = ""
    /// Wrong keystrokes, including the ones corrected later.
    private(set) var errors = 0
    private var keystrokes = 0
    private var start: Date?
    private var finished = false

    init(quotes: [Quote] = []) {
        self.quotes = quotes
        target = quotes.map(\.text).joined(separator: " ")
    }

    /// Takes the field's whole text. Returns the final score on the keystroke that completes the round, nil on
    /// every other one; once complete, typing is ignored.
    @discardableResult
    mutating func type(_ text: String, now: Date = Date()) -> (wpm: Double, accuracy: Double, seconds: Double)? {
        guard !finished else { return nil }
        let goal = Array(target)
        let new = Array(text.prefix(goal.count))
        let old = Array(typed)
        if start == nil, !new.isEmpty { start = now }
        if new.count > old.count {
            for i in old.count..<new.count {
                keystrokes += 1
                if new[i] != goal[i] { errors += 1 }
            }
        } else if new.count == old.count, let i = new.indices.last, new[i] != old[i] {
            // A dead key composed in place (´ then á): re-score that keystroke.
            if old[i] != goal[i] { errors -= 1 }
            if new[i] != goal[i] { errors += 1 }
        }
        typed = String(new)
        let pendingAccent = new.last.map { "´¨`^~ˆ˜".contains($0) && $0 != goal.last } ?? false
        guard new.count == goal.count, !pendingAccent, let start, let s = live(now: now) else { return nil }
        finished = true
        return (s.wpm, s.accuracy, now.timeIntervalSince(start))
    }

    /// Stats so far; nil until the first keystroke. WPM counts only correct characters; accuracy counts every
    /// keystroke, including corrected mistakes.
    func live(now: Date = Date()) -> (wpm: Double, accuracy: Double)? {
        guard let start else { return nil }
        let seconds = now.timeIntervalSince(start)
        let wpm = seconds > 0 ? Double(correct) / 5 / (seconds / 60) : 0
        let accuracy = keystrokes > 0 ? Double(keystrokes - errors) / Double(keystrokes) : 1
        return (wpm, accuracy)
    }

    /// Typed characters that match the target at the same position.
    var correct: Int { zip(target, typed).filter { $0 == $1 }.count }

    /// Source of the quote under the cursor; nil for unattributed quotes.
    var source: String? {
        var end = 0
        for quote in quotes {
            end += quote.text.count + 1
            if typed.count < end { return quote.source }
        }
        return quotes.last?.source
    }
}
