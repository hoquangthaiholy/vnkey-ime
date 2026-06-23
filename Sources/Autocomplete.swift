import Foundation

public struct AutocompleteWord {
    public let original: String
    public let lowercased: String
    public let stripped: String
}

public class Autocomplete {
    private var words: [AutocompleteWord] = []
    
    // Pre-computed prefix maps for O(1) autocomplete lookups
    private var accentedPrefixMap: [String: [AutocompleteWord]] = [:]
    private var strippedPrefixMap: [String: [AutocompleteWord]] = [:]
    
    public init() {
        // Load from app bundle resources
        if let path = Bundle.main.path(forResource: "Viet11K", ofType: "txt") {
            loadWordlist(from: path)
        } else {
            // Check current directory or Sources/ as fallback (useful during local tests)
            let localPath = "Viet11K.txt"
            let sourcesPath = "Sources/Viet11K.txt"
            if FileManager.default.fileExists(atPath: localPath) {
                loadWordlist(from: localPath)
            } else if FileManager.default.fileExists(atPath: sourcesPath) {
                loadWordlist(from: sourcesPath)
            } else {
                NSLog("Viet11K.txt not found in bundle or local path.")
                setFallbackWords()
            }
        }
    }
    
    private func loadWordlist(from path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            var uniqueWords = Set<String>()
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    uniqueWords.insert(trimmed)
                }
            }
            let sortedWords = Array(uniqueWords).sorted { (w1, w2) -> Bool in
                // Prioritize shorter words first, then alphabetical order
                if w1.count != w2.count {
                    return w1.count < w2.count
                }
                return w1 < w2
            }
            self.words = sortedWords.map { word in
                AutocompleteWord(
                    original: word,
                    lowercased: word.lowercased(),
                    stripped: stripDiacritics(word.lowercased())
                )
            }
            buildPrefixMaps()
            NSLog("Successfully loaded \(self.words.count) words and built prefix maps for autocomplete.")
        } catch {
            NSLog("Failed to load wordlist from \(path): \(error)")
            setFallbackWords()
        }
    }
    
    private func setFallbackWords() {
        let fallback = ["học", "chơi", "ăn", "uống", "ngủ", "chạy", "nhảy", "đi", "làm", "viết", "đọc", "nói", "nghe"]
        self.words = fallback.map { word in
            AutocompleteWord(
                original: word,
                lowercased: word.lowercased(),
                stripped: stripDiacritics(word.lowercased())
            )
        }
        buildPrefixMaps()
    }
    
    private func buildPrefixMaps() {
        accentedPrefixMap.removeAll()
        strippedPrefixMap.removeAll()
        
        for word in words {
            // Accented prefixes
            let accented = word.lowercased
            for i in 1...accented.count {
                let prefix = String(accented.prefix(i))
                if accentedPrefixMap[prefix] == nil {
                    accentedPrefixMap[prefix] = []
                }
                if accentedPrefixMap[prefix]!.count < 10 {
                    accentedPrefixMap[prefix]!.append(word)
                }
            }
            
            // Stripped prefixes
            let stripped = word.stripped
            for i in 1...stripped.count {
                let prefix = String(stripped.prefix(i))
                if strippedPrefixMap[prefix] == nil {
                    strippedPrefixMap[prefix] = []
                }
                // Avoid adding the exact same word twice to the same stripped prefix list
                if strippedPrefixMap[prefix]!.count < 10 && !strippedPrefixMap[prefix]!.contains(where: { $0.original == word.original }) {
                    strippedPrefixMap[prefix]!.append(word)
                }
            }
        }
    }
    
    // Returns up to 5 suggestions starting with the prefix (preserving case of prefix)
    public func getSuggestions(prefix: String) -> [String] {
        if prefix.isEmpty { return [] }
        let lowerPrefix = prefix.lowercased()
        let strippedPrefix = stripDiacritics(lowerPrefix)
        
        var matches: [String] = []
        var matchedSet = Set<String>()
        
        // Pass 1: Exact matches (including accents)
        if let candidates = accentedPrefixMap[lowerPrefix] {
            for word in candidates {
                if word.lowercased != lowerPrefix {
                    let suggestion = restoreCapitalization(source: word.original, target: prefix)
                    if !matchedSet.contains(suggestion) {
                        matches.append(suggestion)
                        matchedSet.insert(suggestion)
                        if matches.count >= 5 {
                            break
                        }
                    }
                }
            }
        }
        
        if matches.count >= 5 {
            return matches
        }
        
        // Pass 2: Diacritic-insensitive matches (ignoring accents)
        if let candidates = strippedPrefixMap[strippedPrefix] {
            for word in candidates {
                if word.stripped != strippedPrefix {
                    let suggestion = restoreCapitalization(source: word.original, target: prefix)
                    if !matchedSet.contains(suggestion) {
                        matches.append(suggestion)
                        matchedSet.insert(suggestion)
                        if matches.count >= 5 {
                            break
                        }
                    }
                }
            }
        }
        
        return matches
    }
    
    private func stripDiacritics(_ string: String) -> String {
        // ASCII fast path: if all characters are standard ASCII, they don't have diacritics
        if string.utf8.allSatisfy({ $0 < 128 }) {
            return string
        }
        let folded = string.folding(options: .diacriticInsensitive, locale: nil)
        return folded
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
    }
    
    private func restoreCapitalization(source: String, target: String) -> String {
        let isTargetAllUpper = target.allSatisfy { !$0.isLetter || $0.isUppercase }
        let isTargetFirstUpper = target.first?.isUppercase ?? false
        
        if isTargetAllUpper {
            return source.uppercased()
        } else if isTargetFirstUpper {
            if let first = source.first {
                return String(first).uppercased() + source.dropFirst()
            }
        }
        return source.lowercased()
    }
}
