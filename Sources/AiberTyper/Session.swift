import Foundation
import Observation

@Observable final class Session {
    private(set) var lang: Lang
    private(set) var collection: Collection
    /// Built-in collections, then the ones in `folder`; refreshed when the picker or the Colección menu opens and after an import.
    private(set) var collections = Collection.builtIn
    /// Files in `folder` that could not be used, one message each.
    private(set) var problems: [String] = []
    private(set) var favorites: Set<String>
    let folder: URL
    private(set) var round = Round()
    private(set) var result: RoundResult?
    private(set) var averageBefore: Double?
    /// The finished round beats every saved round (never true on the first one).
    private(set) var isRecord = false
    private(set) var note = ""
    /// Counts rounds started, so the view can refocus the field on each one.
    private(set) var roundNumber = 0
    /// The panel is on screen; the live stats only tick while it is.
    var visible = false

    private var history: History
    /// Where `lang`, `pack` and `favorites` are saved.
    private let defaults: UserDefaults

    init(history: History = History(), folder: URL = Collection.folder, defaults: UserDefaults = .standard) {
        self.history = history
        self.folder = folder
        self.defaults = defaults
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        lang = Lang(rawValue: defaults.string(forKey: "lang") ?? "") ?? .es
        collection = .general
        reloadCollections() // switches to the saved collection when it loads
        if roundNumber == 0 { newRound() }
    }

    func newRound() {
        // First run has no history: assume an average typist (40 wpm).
        let wpm = history.recentWPM ?? 40
        round = Round(quotes: pickSentences(from: collection.quotes(lang), chars: charsFor(wpm: wpm, seconds: .random(in: 30...60)),
                                            maxChars: charsFor(wpm: wpm, seconds: 90)))
        result = nil
        isRecord = false
        note = ""
        roundNumber += 1
    }

    func toggleLanguage() {
        lang = lang.toggled
        defaults.set(lang.rawValue, forKey: "lang")
        newRound()
    }

    func choose(_ collection: Collection) {
        self.collection = collection
        picking = false
        defaults.set(collection.id, forKey: "pack")
        newRound()
    }

    /// Rereads `folder`. A chosen collection whose file is gone falls back to General in memory only:
    /// the saved `pack` is kept and comes back once its file loads again.
    func reloadCollections() {
        let loaded = Collection.load(from: folder)
        collections = Collection.builtIn + loaded.collections
        problems = loaded.problems
        let saved = defaults.string(forKey: "pack")
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
        defaults.set(Array(favorites), forKey: "favorites")
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

    /// Types into the round and, on the keystroke that completes it, saves the result to the history.
    func type(_ text: String, now: Date = Date()) {
        guard let s = round.type(text, now: now) else { return }
        let result = RoundResult(date: now, lang: lang, wpm: s.wpm, accuracy: s.accuracy, seconds: s.seconds)
        averageBefore = history.recentWPM
        isRecord = history.rounds.map(\.wpm).max().map { s.wpm > $0 } ?? false
        do {
            try history.add(result)
        } catch {
            note = "No se pudo guardar el historial: \(error.localizedDescription)"
        }
        self.result = result
    }

    /// WPM of the last 20 saved rounds, oldest first; after a round it ends with that round.
    var recentWPMs: [Double] { history.rounds.suffix(20).map(\.wpm) }
}
