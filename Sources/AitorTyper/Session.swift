import Foundation
import Observation

@Observable final class Session {
    private(set) var lang: Lang
    var target = ""
    private(set) var typed = ""
    private(set) var result: RoundResult?
    private(set) var averageBefore: Double?
    private(set) var note = ""
    private(set) var round = 0

    private var start: Date?
    private var keystrokes = 0
    private var errors = 0
    private var history: History

    init(history: History = History()) {
        self.history = history
        lang = Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "") ?? .es
        newRound()
    }

    func newRound() {
        var rng = SystemRandomNumberGenerator()
        // First run has no history: assume an average typist (40 wpm).
        let chars = charsFor(wpm: history.recentWPM ?? 40, seconds: .random(in: 30...60))
        target = makeText(from: lang.sentences, chars: chars, using: &rng)
        typed = ""
        result = nil
        note = ""
        start = nil
        keystrokes = 0
        errors = 0
        round += 1
    }

    func toggleLanguage() {
        lang = lang.toggled
        UserDefaults.standard.set(lang.rawValue, forKey: "lang")
        newRound()
    }

    func type(_ text: String, now: Date = Date()) {
        guard result == nil else { return }
        let goal = Array(target)
        let new = Array(text.prefix(goal.count))
        let old = Array(typed)
        if start == nil, !new.isEmpty { start = now }
        if new.count > old.count {
            for i in old.count..<new.count {
                keystrokes += 1
                if new[i] != goal[i] { errors += 1 }
            }
        }
        typed = String(new)
        if new.count == goal.count, let start { finish(seconds: now.timeIntervalSince(start), now: now) }
    }

    /// Stats of the round so far; nil until the first keystroke.
    func live(now: Date = Date()) -> (wpm: Double, accuracy: Double)? {
        guard let start else { return nil }
        return score(target: target, typed: typed, seconds: now.timeIntervalSince(start), keystrokes: keystrokes, errors: errors)
    }

    private func finish(seconds: Double, now: Date) {
        let s = score(target: target, typed: typed, seconds: seconds, keystrokes: keystrokes, errors: errors)
        let round = RoundResult(date: now, lang: lang, wpm: s.wpm, accuracy: s.accuracy, seconds: seconds)
        averageBefore = history.recentWPM
        do {
            try history.add(round)
        } catch {
            note = "No se pudo guardar el historial: \(error.localizedDescription)"
        }
        result = round
    }
}
