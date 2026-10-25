import Foundation
import Observation

@Observable final class Session {
    private(set) var lang: Lang
    private(set) var collection: Collection
    /// Built-in collections, then the ones in `folder`; refreshed when the picker or the Colección menu opens and after an import.
    private(set) var collections = Collection.builtIn
    /// Files in `folder` that could not be used, one message each.
    private(set) var problems: [String] = []
    private(set) var favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
    let folder: URL
    private(set) var target = ""
    /// The sentences that make up `target`, in order.
    private(set) var quotes: [Quote] = []
    private(set) var typed = ""
    private(set) var result: RoundResult?
    private(set) var averageBefore: Double?
    /// The finished round beats every saved round (never true on the first one).
    private(set) var isRecord = false
    private(set) var note = ""
    private(set) var round = 0
    /// The panel is on screen; the live stats only tick while it is.
    var visible = false

    private var start: Date?
    private var keystrokes = 0
    /// Wrong keystrokes, including the ones corrected later.
    private(set) var errors = 0
    private var history: History

    init(history: History = History(), folder: URL = Collection.folder) {
        self.history = history
        self.folder = folder
        lang = Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "") ?? .es
        collection = .general
        reloadCollections() // switches to the saved collection when it loads
        if round == 0 { newRound() }
    }

    func newRound() {
        // First run has no history: assume an average typist (40 wpm).
        let wpm = history.recentWPM ?? 40
        quotes = pickSentences(from: collection.quotes(lang), chars: charsFor(wpm: wpm, seconds: .random(in: 30...60)),
                               maxChars: charsFor(wpm: wpm, seconds: 90))
        target = quotes.map(\.text).joined(separator: " ")
        typed = ""
        result = nil
        isRecord = false
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

    func choose(_ collection: Collection) {
        self.collection = collection
        picking = false
        UserDefaults.standard.set(collection.id, forKey: "pack")
        newRound()
    }

    /// Rereads `folder`. A chosen collection whose file is gone falls back to General in memory only:
    /// the saved `pack` is kept and comes back once its file loads again.
    func reloadCollections() {
        let loaded = Collection.load(from: folder)
        collections = Collection.builtIn + loaded.collections
        problems = loaded.problems
        let saved = UserDefaults.standard.string(forKey: "pack")
        if saved != collection.id, let wanted = collections.first(where: { $0.id == saved }) {
            collection = wanted
            newRound()
        } else if let fresh = collections.first(where: { $0.id == collection.id }) {
            collection = fresh
        } else {
            collection = .general
            newRound()
        }
    }

    /// Favorites first, each group in its original order.
    var sortedCollections: [Collection] {
        collections.filter { favorites.contains($0.id) } + collections.filter { !favorites.contains($0.id) }
    }

    // Collection picker: a filterable list opened with ⇧Tab.
    private(set) var picking = false
    private(set) var filter = ""
    private(set) var selection = 0

    var matches: [Collection] {
        filter.isEmpty ? sortedCollections : sortedCollections.filter { $0.name.localizedStandardContains(filter) }
    }

    func openPicker() {
        reloadCollections()
        filter = ""
        selection = matches.firstIndex { $0.id == collection.id } ?? 0
        picking = true
    }

    /// Stars or unstars the selected collection, keeping it selected as it moves.
    func toggleFavoritePicked() {
        guard matches.indices.contains(selection) else { return }
        let picked = matches[selection]
        if favorites.remove(picked.id) == nil { favorites.insert(picked.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
        selection = matches.firstIndex { $0.id == picked.id } ?? 0
    }

    func closePicker() { picking = false }

    func movePicker(_ step: Int) {
        selection = max(0, min(selection + step, matches.count - 1))
    }

    /// Adds printable characters to the filter; newlines, control and private-use characters (arrow keys) are dropped.
    func typeInPicker(_ chars: String) {
        let printable = chars.filter { char in
            !char.isNewline && !char.unicodeScalars.contains { [.control, .privateUse].contains($0.properties.generalCategory) }
        }
        guard !printable.isEmpty else { return }
        filter += printable
        selection = 0
    }

    func deleteInPicker() {
        guard !filter.isEmpty else { return }
        filter = String(filter.dropLast())
        selection = 0
    }

    func choosePicked() { chooseMatch(at: selection) }

    /// Chooses the row at `index`, as a mouse click on it does.
    func chooseMatch(at index: Int) {
        guard matches.indices.contains(index) else { return }
        choose(matches[index])
    }

    /// Source of the sentence under the cursor; nil for unattributed sentences.
    var source: String? {
        var end = 0
        for quote in quotes {
            end += quote.text.count + 1
            if typed.count < end { return quote.source }
        }
        return quotes.last?.source
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
        } else if new.count == old.count, let i = new.indices.last, new[i] != old[i] {
            // A dead key composed in place (´ then á): re-score that keystroke.
            if old[i] != goal[i] { errors -= 1 }
            if new[i] != goal[i] { errors += 1 }
        }
        typed = String(new)
        let pendingAccent = new.last.map { "´¨`^~ˆ˜".contains($0) && $0 != goal.last } ?? false
        if new.count == goal.count, !pendingAccent { finish(now: now) }
    }

    /// Stats of the round so far; nil until the first keystroke.
    func live(now: Date = Date()) -> (wpm: Double, accuracy: Double)? {
        guard let start else { return nil }
        return score(target: target, typed: typed, seconds: now.timeIntervalSince(start), keystrokes: keystrokes, errors: errors)
    }

    /// WPM of the last 20 saved rounds, oldest first; after a round it ends with that round.
    var recentWPMs: [Double] { history.rounds.suffix(20).map(\.wpm) }

    var correct: Int { correctChars(target: target, typed: typed) }

    private func finish(now: Date) {
        guard let start, let s = live(now: now) else { return }
        let round = RoundResult(date: now, lang: lang, wpm: s.wpm, accuracy: s.accuracy, seconds: now.timeIntervalSince(start))
        averageBefore = history.recentWPM
        isRecord = history.rounds.map(\.wpm).max().map { s.wpm > $0 } ?? false
        do {
            try history.add(round)
        } catch {
            note = "No se pudo guardar el historial: \(error.localizedDescription)"
        }
        result = round
    }
}
