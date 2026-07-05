import Foundation

/// Learns simple word-pair ("bigram") frequencies from the user's own typing —
/// entirely on-device, nothing leaves the machine — and uses them to predict
/// the word that's likely to come next, right after the previous word is
/// committed. Seeded with a small set of common Vietnamese pairs so it's
/// useful immediately, then keeps adapting to the user's own habits from there.
public class NextWordPredictor {
    public static let shared = NextWordPredictor()

    private static let defaultsKey = "nextWordBigrams"
    // Cap how many distinct next-words are remembered per previous word, and
    // how many distinct previous words the whole table can hold, so this can't
    // grow unbounded over months/years of use.
    private static let maxNextWordsPerKey = 8
    private static let maxDistinctPreviousWords = 2000

    private let defaults = UserDefaults.standard
    private var table: [String: [String: Int]]

    private static let seedBigrams: [String: [String: Int]] = [
        "cảm": ["ơn": 5],
        "xin": ["chào": 5, "lỗi": 4, "phép": 2],
        "rất": ["vui": 4, "tốt": 3, "nhiều": 3, "tiếc": 2],
        "chào": ["bạn": 3, "buổi": 2],
        "tạm": ["biệt": 5],
        "chúc": ["mừng": 3, "bạn": 2],
        "hẹn": ["gặp": 4],
        "không": ["sao": 3, "có": 3, "biết": 2],
        "có": ["thể": 3, "lẽ": 2],
        "một": ["cách": 2, "chút": 2, "số": 2],
    ]

    public init() {
        table = Self.decodeTable(defaults.dictionary(forKey: Self.defaultsKey)) ?? Self.seedBigrams
    }

    /// Records that `next` was typed right after `previous`. Stored lowercase
    /// since capitalization is contextual (start of sentence, proper nouns)
    /// while the diacritics that actually change word meaning are preserved.
    public func recordTransition(from previous: String, to next: String) {
        guard !previous.isEmpty, !next.isEmpty else { return }
        let key = previous.lowercased()
        let value = next.lowercased()

        // Bound total table growth: once at the cap, don't start tracking
        // brand-new previous words (existing ones can still refine further).
        if table[key] == nil && table.count >= Self.maxDistinctPreviousWords {
            return
        }

        var nextWords = table[key] ?? [:]
        nextWords[value, default: 0] += 1

        if nextWords.count > Self.maxNextWordsPerKey {
            let trimmed = nextWords.sorted { $0.value > $1.value }.prefix(Self.maxNextWordsPerKey)
            nextWords = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }

        table[key] = nextWords

        // recordTransition runs synchronously on the same (main) thread as key
        // handling, once per committed word — the caller (VnInputController)
        // is on the hot path for every keystroke. Measured at the table's own
        // maxDistinctPreviousWords cap, serializing the whole dictionary back
        // to UserDefaults here took ~4-5ms; on a background queue it can't add
        // to per-keystroke latency. `table` is a value type, so the snapshot
        // captured below is independent of whatever `self.table` becomes next.
        let snapshot = table
        let defaults = self.defaults
        DispatchQueue.global(qos: .utility).async {
            defaults.set(snapshot, forKey: Self.defaultsKey)
        }
    }

    /// Returns up to `limit` next-word predictions for what typically follows
    /// `previous`, most frequent first.
    public func predictNextWords(after previous: String, limit: Int = 5) -> [String] {
        guard !previous.isEmpty, let nextWords = table[previous.lowercased()] else { return [] }
        return nextWords.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Discards everything learned from the user's typing, falling back to
    /// just the built-in seed pairs again. Useful when heavy testing/repeated
    /// words have skewed the learned frequencies away from real usage.
    public func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
        table = Self.seedBigrams
    }

    // UserDefaults.dictionary(forKey:) round-trips as [String: Any] with the
    // inner dictionaries type-erased too, so a direct `as? [String: [String: Int]]`
    // cast doesn't always succeed — rebuild it by hand instead.
    private static func decodeTable(_ raw: [String: Any]?) -> [String: [String: Int]]? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        var rebuilt: [String: [String: Int]] = [:]
        for (key, value) in raw {
            guard let innerAny = value as? [String: Any] else { continue }
            var inner: [String: Int] = [:]
            for (innerKey, innerValue) in innerAny {
                if let n = innerValue as? Int {
                    inner[innerKey] = n
                } else if let n = innerValue as? NSNumber {
                    inner[innerKey] = n.intValue
                }
            }
            if !inner.isEmpty {
                rebuilt[key] = inner
            }
        }
        return rebuilt.isEmpty ? nil : rebuilt
    }
}
