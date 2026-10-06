import Foundation

/// Learns word-pair ("bigram") frequencies from the user's own typing —
/// entirely on-device, nothing leaves the machine — and combines them with a
/// rich pre-loaded Vietnamese bigram dictionary to predict the word that's
/// likely to come next, right after the previous word is committed.
///
/// Words that the user types preserve their exact original capitalization / casing,
/// and frequently typed words are automatically boosted to the top of suggestions.
public class NextWordPredictor {
    public static let shared = NextWordPredictor()

    private static let defaultsKey = "nextWordBigrams"
    private static let maxNextWordsPerKey = 8
    private static let maxDistinctPreviousWords = 5000
    private static let userFrequencyMultiplier = 20

    private let defaults = UserDefaults.standard
    private var baselineBigrams: [String: [String: Int]] = [:]
    private var userLearnedTable: [String: [String: Int]] = [:]

    private static let defaultSeedBigrams: [String: [String: Int]] = [
        "cảm": ["ơn": 100, "thấy": 80, "giác": 70, "nhận": 60],
        "xin": ["chào": 100, "lỗi": 90, "phép": 80, "hỏi": 70],
        "rất": ["tốt": 100, "nhiều": 90, "vui": 85, "đẹp": 80, "hay": 75],
        "chào": ["bạn": 100, "mừng": 90, "buổi": 80, "anh": 75, "chị": 75],
        "tạm": ["biệt": 100, "thời": 90, "trú": 70],
        "chúc": ["mừng": 100, "bạn": 90, "ngủ": 85, "sức": 80, "tết": 75],
        "hẹn": ["gặp": 100, "lại": 90, "hò": 70],
        "không": ["có": 100, "thể": 95, "được": 90, "phải": 85, "biết": 80],
        "có": ["thể": 100, "lẽ": 90, "được": 85, "nhiều": 80],
        "một": ["cách": 100, "số": 90, "chút": 85, "vài": 80],
        "học": ["tập": 100, "sinh": 95, "hỏi": 85, "hành": 80],
        "làm": ["việc": 100, "sao": 90, "gì": 85, "được": 80, "chủ": 75],
        "phát": ["triển": 100, "hiện": 90, "hành": 85, "biểu": 80],
        "thành": ["phố": 100, "công": 95, "viên": 90, "lập": 85],
        "chúng": ["tôi": 100, "ta": 95, "mình": 80],
        "người": ["dùng": 100, "dân": 90, "ta": 85, "lớn": 80, "yêu": 75],
    ]

    public init() {
        loadBaselineBigrams()
        userLearnedTable = Self.decodeTable(defaults.dictionary(forKey: Self.defaultsKey)) ?? [:]
    }

    private func loadBaselineBigrams() {
        var content: String?
        if let path = Bundle.main.path(forResource: "bigrams", ofType: "txt") {
            content = try? String(contentsOfFile: path, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: "Sources/bigrams.txt") {
            content = try? String(contentsOfFile: "Sources/bigrams.txt", encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: "bigrams.txt") {
            content = try? String(contentsOfFile: "bigrams.txt", encoding: .utf8)
        }

        guard let rawContent = content, !rawContent.isEmpty else {
            NSLog("NextWordPredictor: using default seed bigrams")
            baselineBigrams = Self.defaultSeedBigrams
            return
        }

        var map: [String: [String: Int]] = [:]
        let lines = rawContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parts = trimmed.components(separatedBy: " ")
            if parts.count >= 3, let freq = Int(parts[2]) {
                let prev = parts[0].lowercased()
                let next = parts[1]
                if map[prev] == nil {
                    map[prev] = [:]
                }
                map[prev]![next] = freq
            }
        }

        baselineBigrams = map.isEmpty ? Self.defaultSeedBigrams : map
        NSLog("NextWordPredictor: loaded \(baselineBigrams.count) baseline bigram keys")
    }

    /// Records that `next` was typed right after `previous`.
    /// Preserves the exact original upper/lower casing of the `next` word as typed by the user.
    public func recordTransition(from previous: String, to next: String) {
        let trimmedPrev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNext = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrev.isEmpty, !trimmedNext.isEmpty else { return }

        let key = trimmedPrev.lowercased()
        let value = trimmedNext // Preserve exact casing as typed

        if userLearnedTable[key] == nil && userLearnedTable.count >= Self.maxDistinctPreviousWords {
            return
        }

        var nextWords = userLearnedTable[key] ?? [:]
        nextWords[value, default: 0] += 1

        if nextWords.count > Self.maxNextWordsPerKey {
            let trimmed = nextWords.sorted { $0.value > $1.value }.prefix(Self.maxNextWordsPerKey)
            nextWords = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }

        userLearnedTable[key] = nextWords

        let snapshot = userLearnedTable
        let defaults = self.defaults
        DispatchQueue.global(qos: .utility).async {
            defaults.set(snapshot, forKey: Self.defaultsKey)
        }
    }

    /// Returns up to `limit` next-word predictions for what typically follows `previous`.
    /// Preserves the learned casing of words, and prioritizes words frequently typed by the user.
    public func predictNextWords(after previous: String, limit: Int = 5) -> [String] {
        let trimmedPrev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrev.isEmpty else { return [] }
        let key = trimmedPrev.lowercased()

        let baseMap = baselineBigrams[key] ?? [:]
        let userMap = userLearnedTable[key] ?? [:]

        if baseMap.isEmpty && userMap.isEmpty {
            return []
        }

        var candidateScores: [String: Int] = [:]

        // 1. Add baseline candidates
        for (baseWord, baseFreq) in baseMap {
            candidateScores[baseWord] = baseFreq
        }

        // 2. Add user learned candidates with boost, overriding baseline casing if user typed custom case
        for (userWord, userCount) in userMap {
            let userScore = userCount * Self.userFrequencyMultiplier
            let lower = userWord.lowercased()
            if let baseFreq = baseMap[lower], userWord != lower {
                candidateScores.removeValue(forKey: lower)
                candidateScores[userWord] = baseFreq + userScore
            } else {
                candidateScores[userWord, default: 0] += userScore
            }
        }

        let sorted = candidateScores.sorted { (a, b) -> Bool in
            if a.value != b.value {
                return a.value > b.value
            }
            return a.key < b.key
        }

        return Array(sorted.prefix(limit).map { $0.key })
    }

    /// Discards everything learned from the user's typing, falling back to
    /// just the baseline bigram dictionary.
    public func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
        userLearnedTable.removeAll()
    }

    // UserDefaults.dictionary(forKey:) helper
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
