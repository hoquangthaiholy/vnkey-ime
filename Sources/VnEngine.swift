import Foundation

public enum InputMethod {
    case telex
    case vni
}

public enum Tone: Int {
    case none = 0
    case sac = 1
    case huyen = 2
    case hoi = 3
    case nga = 4
    case nang = 5
}

public struct SyllableState {
    public var onset: String = ""
    public var vowels: String = ""
    public var coda: String = ""
    public var tone: Tone = .none
    
    // Track applied modifiers to support toggling/cancelling
    public var hatApplied: Bool = false
    public var whiskerApplied: Bool = false
    public var ddApplied: Bool = false
    
    // When a modifier is cancelled or not applicable, we store it literally
    public var literalSuffix: String = ""
    
    public init() {}
}

public class VnEngine {
    
    private static let vowelSet: Set<Character> = [
        "a", "e", "o", "i", "u", "y",
        "â", "ă", "ê", "ô", "ơ", "ư",
        "A", "E", "O", "I", "U", "Y",
        "Â", "Ă", "Ê", "Ô", "Ơ", "Ư"
    ]
    
    private static let toneMap: [Character: [Character]] = [
        "a": ["a", "á", "à", "ả", "ã", "ạ"],
        "ă": ["ă", "ắ", "ằ", "ẳ", "ẵ", "ặ"],
        "â": ["â", "ấ", "ầ", "ẩ", "ẫ", "ậ"],
        "e": ["e", "é", "è", "ẻ", "ẽ", "ẹ"],
        "ê": ["ê", "ế", "ề", "ể", "ễ", "ệ"],
        "i": ["i", "í", "ì", "ỉ", "ĩ", "ị"],
        "o": ["o", "ó", "ò", "ỏ", "õ", "ọ"],
        "ô": ["ô", "ố", "ồ", "ổ", "ỗ", "ộ"],
        "ơ": ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"],
        "u": ["u", "ú", "ù", "ủ", "ũ", "ụ"],
        "ư": ["ư", "ứ", "ừ", "ử", "ữ", "ự"],
        "y": ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"]
    ]
    
    public static func isVowel(_ char: Character) -> Bool {
        return vowelSet.contains(char)
    }
    
    // Processes a raw string typed so far and returns the translated Vietnamese word
    public static func process(raw: String, method: InputMethod) -> String {
        if raw.isEmpty { return "" }
        
        // Preserve capitalization information
        let isAllUpper = raw.allSatisfy { !$0.isLetter || $0.isUppercase }
        let isFirstUpper = raw.first?.isUppercase ?? false
        
        let normalizedRaw = raw.lowercased()
        var state = SyllableState()
        
        // Pre-detect special consonant glides: "qu" and "gi"
        var remaining = normalizedRaw
        
        if remaining.hasPrefix("qu") {
            state.onset = "qu"
            remaining = String(remaining.dropFirst(2))
        } else if remaining.hasPrefix("gi") {
            // Check if there is another vowel after "gi" (e.g. "giang", "giúp")
            // If yes, then "gi" is the onset.
            // If no (e.g. "gì", "gình"), then "g" is the onset and "i" is the vowel.
            let hasFollowingVowel = remaining.dropFirst(2).contains { char in
                isVowel(char) || char == "6" || char == "7" || char == "8" || char == "w"
            }
            if hasFollowingVowel {
                state.onset = "gi"
                remaining = String(remaining.dropFirst(2))
            } else {
                state.onset = "g"
                remaining = String(remaining.dropFirst(1))
            }
        }
        
        // Process character by character
        for char in remaining {
            let isCharVowel = isVowel(char)
            
            // 1. Check if it's a tone key
            if isToneKey(char, method: method) && !state.vowels.isEmpty {
                handleToneKey(char, state: &state, method: method)
                continue
            }
            
            // 2. Check if it's a diacritic modifier key
            if isDiacriticKey(char, method: method) {
                var isValidMod = false
                if method == .telex {
                    if char == "w" && !state.vowels.isEmpty {
                        isValidMod = true
                    } else if char == "d" {
                        if state.onset == "d" || (state.onset == "đ" && state.ddApplied) {
                            isValidMod = true
                        }
                    }
                } else if method == .vni {
                    if char == "6" && !state.vowels.isEmpty {
                        isValidMod = true
                    } else if char == "7" && !state.vowels.isEmpty {
                        isValidMod = true
                    } else if char == "8" && state.vowels.contains("a") {
                        isValidMod = true
                    } else if char == "9" {
                        if state.onset == "d" || (state.onset == "đ" && state.ddApplied) {
                            isValidMod = true
                        }
                    }
                }
                
                if isValidMod {
                    handleDiacriticKey(char, state: &state, method: method)
                    continue
                }
            }
            
            // 3. Regular vowel or consonant
            if isCharVowel {
                // Telex late double-vowel modifier check (e.g. typing 'o' at the end of 'mọt' to get 'một')
                var isDoubleVowelModifier = false
                if method == .telex {
                    if char == "a" && (state.vowels.contains("a") || state.vowels.contains("â")) {
                        isDoubleVowelModifier = true
                    } else if char == "e" && (state.vowels.contains("e") || state.vowels.contains("ê")) {
                        isDoubleVowelModifier = true
                    } else if char == "o" && (state.vowels.contains("o") || state.vowels.contains("ô")) {
                        isDoubleVowelModifier = true
                    }
                }
                
                if (!state.coda.isEmpty || !state.literalSuffix.isEmpty) && !isDoubleVowelModifier {
                    // Vowels should be contiguous. If coda or literal suffix exists, treat as literal suffix.
                    state.literalSuffix.append(char)
                } else {
                    // Check Telex double-vowel rules before appending
                    if method == .telex {
                        if char == "a" {
                            if state.vowels.contains("a") {
                                state.vowels = state.vowels.replacingOccurrences(of: "a", with: "â")
                                state.hatApplied = true
                                continue
                            } else if state.vowels.contains("â") && state.hatApplied {
                                state.vowels = state.vowels.replacingOccurrences(of: "â", with: "a")
                                state.hatApplied = false
                                state.literalSuffix.append("a")
                                continue
                            }
                        } else if char == "e" {
                            if state.vowels.contains("e") {
                                state.vowels = state.vowels.replacingOccurrences(of: "e", with: "ê")
                                state.hatApplied = true
                                continue
                            } else if state.vowels.contains("ê") && state.hatApplied {
                                state.vowels = state.vowels.replacingOccurrences(of: "ê", with: "e")
                                state.hatApplied = false
                                state.literalSuffix.append("e")
                                continue
                            }
                        } else if char == "o" {
                            if state.vowels.contains("o") {
                                state.vowels = state.vowels.replacingOccurrences(of: "o", with: "ô")
                                state.hatApplied = true
                                continue
                            } else if state.vowels.contains("ô") && state.hatApplied {
                                state.vowels = state.vowels.replacingOccurrences(of: "ô", with: "o")
                                state.hatApplied = false
                                state.literalSuffix.append("o")
                                continue
                            }
                        }
                    }
                    state.vowels.append(char)
                }
            } else {
                // Consonant
                if state.vowels.isEmpty {
                    // Still in the onset
                    if method == .telex && char == "d" && state.onset == "d" {
                        state.onset = "đ"
                        state.ddApplied = true
                    } else {
                        state.onset.append(char)
                    }
                } else {
                    // In the coda
                    if !state.literalSuffix.isEmpty {
                        state.literalSuffix.append(char)
                    } else {
                        state.coda.append(char)
                    }
                }
            }
        }
        
        // Assemble parts and apply tone
        var finalVowels = state.vowels
        if state.tone != .none && !finalVowels.isEmpty {
            finalVowels = applyTone(to: finalVowels, coda: state.coda, tone: state.tone)
        }
        
        var result = state.onset + finalVowels + state.coda + state.literalSuffix
        
        // Restore capitalization
        if isAllUpper {
            result = result.uppercased()
        } else if isFirstUpper {
            if let first = result.first {
                result = String(first).uppercased() + result.dropFirst()
            }
        }
        
        return result
    }
    
    // MARK: - Helper Methods
    
    private static func isToneKey(_ char: Character, method: InputMethod) -> Bool {
        switch method {
        case .telex:
            switch char {
            case "s", "f", "r", "x", "j", "z": return true
            default: return false
            }
        case .vni:
            switch char {
            case "1", "2", "3", "4", "5", "0": return true
            default: return false
            }
        }
    }
    
    private static func isDiacriticKey(_ char: Character, method: InputMethod) -> Bool {
        switch method {
        case .telex:
            return char == "w" || char == "d"
        case .vni:
            switch char {
            case "6", "7", "8", "9": return true
            default: return false
            }
        }
    }
    
    private static func handleToneKey(_ char: Character, state: inout SyllableState, method: InputMethod) {
        let newTone: Tone
        switch method {
        case .telex:
            switch char {
            case "s": newTone = .sac
            case "f": newTone = .huyen
            case "r": newTone = .hoi
            case "x": newTone = .nga
            case "j": newTone = .nang
            default: newTone = .none
            }
        case .vni:
            switch char {
            case "1": newTone = .sac
            case "2": newTone = .huyen
            case "3": newTone = .hoi
            case "4": newTone = .nga
            case "5": newTone = .nang
            default: newTone = .none
            }
        }
        
        if state.tone == newTone && newTone != .none {
            // Toggle/Cancel tone: remove tone and append literal key
            state.tone = .none
            state.literalSuffix.append(char)
        } else {
            // Apply new tone
            state.tone = newTone
        }
    }
    
    private static func handleDiacriticKey(_ char: Character, state: inout SyllableState, method: InputMethod) {
        if method == .telex {
            if char == "w" {
                if state.whiskerApplied {
                    // Revert whisker
                    state.vowels = revertWhisker(state.vowels)
                    state.whiskerApplied = false
                    state.literalSuffix.append("w")
                } else {
                    // Apply whisker
                    let modified = applyWhisker(state.vowels)
                    if modified != state.vowels {
                        state.vowels = modified
                        state.whiskerApplied = true
                    } else {
                        state.literalSuffix.append("w")
                    }
                }
            } else if char == "d" {
                if state.onset == "d" {
                    state.onset = "đ"
                    state.ddApplied = true
                } else if state.onset == "đ" && state.ddApplied {
                    state.onset = "d"
                    state.ddApplied = false
                    state.literalSuffix.append("d")
                } else {
                    state.literalSuffix.append("d")
                }
            }
        } else if method == .vni {
            switch char {
            case "6": // Hat (a -> â, e -> ê, o -> ô)
                if state.hatApplied {
                    state.vowels = revertHat(state.vowels)
                    state.hatApplied = false
                    state.literalSuffix.append("6")
                } else {
                    let modified = applyHat(state.vowels)
                    if modified != state.vowels {
                        state.vowels = modified
                        state.hatApplied = true
                    } else {
                        state.literalSuffix.append("6")
                    }
                }
            case "7": // Whisker (o -> ơ, u -> ư)
                if state.whiskerApplied {
                    state.vowels = revertWhisker(state.vowels)
                    state.whiskerApplied = false
                    state.literalSuffix.append("7")
                } else {
                    let modified = applyWhisker(state.vowels)
                    if modified != state.vowels {
                        state.vowels = modified
                        state.whiskerApplied = true
                    } else {
                        state.literalSuffix.append("7")
                    }
                }
            case "8": // Breve (a -> ă)
                if state.vowels.contains("a") {
                    state.vowels = state.vowels.replacingOccurrences(of: "a", with: "ă")
                    state.whiskerApplied = true // Treat breve as whisker/breve toggle
                } else if state.vowels.contains("ă") {
                    state.vowels = state.vowels.replacingOccurrences(of: "ă", with: "a")
                    state.literalSuffix.append("8")
                } else {
                    state.literalSuffix.append("8")
                }
            case "9": // Stroke (d -> đ)
                if state.onset == "d" {
                    state.onset = "đ"
                    state.ddApplied = true
                } else if state.onset == "đ" && state.ddApplied {
                    state.onset = "d"
                    state.ddApplied = false
                    state.literalSuffix.append("9")
                } else {
                    state.literalSuffix.append("9")
                }
            default:
                break
            }
        }
    }
    
    private static func applyWhisker(_ vowels: String) -> String {
        if vowels == "uo" { return "ươ" }
        if vowels == "ua" { return "ưa" }
        if vowels == "oa" { return "oă" }
        if vowels == "oi" { return "ơi" }
        if vowels == "ui" { return "ưi" }
        if vowels == "uoi" { return "ươi" }
        if vowels == "uou" { return "ươu" }
        if vowels == "uu" { return "ưu" }
        if vowels == "u" { return "ư" }
        if vowels == "o" { return "ơ" }
        if vowels == "a" { return "ă" }
        return vowels
    }
    
    private static func revertWhisker(_ vowels: String) -> String {
        if vowels == "ươ" { return "uo" }
        if vowels == "ưa" { return "ua" }
        if vowels == "oă" { return "oa" }
        if vowels == "ơi" { return "oi" }
        if vowels == "ưi" { return "ui" }
        if vowels == "ươi" { return "uoi" }
        if vowels == "ươu" { return "uou" }
        if vowels == "ưu" { return "uu" }
        if vowels == "ư" { return "u" }
        if vowels == "ơ" { return "o" }
        if vowels == "ă" { return "a" }
        return vowels
    }
    
    private static func applyHat(_ vowels: String) -> String {
        if vowels == "ua" { return "uâ" }
        if vowels == "ue" { return "uê" }
        if vowels == "ie" { return "iê" }
        if vowels == "a" { return "â" }
        if vowels == "e" { return "ê" }
        if vowels == "o" { return "ô" }
        return vowels
    }
    
    private static func revertHat(_ vowels: String) -> String {
        if vowels == "uâ" { return "ua" }
        if vowels == "uê" { return "ue" }
        if vowels == "iê" { return "ie" }
        if vowels == "â" { return "a" }
        if vowels == "ê" { return "e" }
        if vowels == "ô" { return "o" }
        return vowels
    }
    
    // MARK: - Tone Placement Algorithm
    
    private static func applyTone(to vowels: String, coda: String, tone: Tone) -> String {
        if vowels.isEmpty { return vowels }
        let targetIndex = getToneVowelIndex(vowels: vowels, coda: coda)
        
        var chars = Array(vowels)
        if targetIndex < chars.count {
            chars[targetIndex] = applyToneToChar(chars[targetIndex], tone: tone)
        }
        return String(chars)
    }
    
    private static func getToneVowelIndex(vowels: String, coda: String) -> Int {
        if vowels.count <= 1 { return 0 }
        
        let lower = vowels.lowercased()
        
        // Rule 1-6: vowels with hats/whiskers get priority
        if let idx = lower.firstIndex(of: "ê") {
            return lower.distance(from: lower.startIndex, to: idx)
        }
        if let idx = lower.firstIndex(of: "â") {
            return lower.distance(from: lower.startIndex, to: idx)
        }
        if let idx = lower.firstIndex(of: "ă") {
            return lower.distance(from: lower.startIndex, to: idx)
        }
        if let idx = lower.firstIndex(of: "ô") {
            return lower.distance(from: lower.startIndex, to: idx)
        }
        
        // For ươ, tone goes on ơ (second vowel)
        if lower.contains("ươ") {
            if let idx = lower.range(of: "ươ")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 1
            }
        }
        
        if let idx = lower.firstIndex(of: "ơ") {
            return lower.distance(from: lower.startIndex, to: idx)
        }
        if let idx = lower.firstIndex(of: "ư") {
            return lower.distance(from: lower.startIndex, to: idx)
        }
        
        // Rule 7-8: uyê, oai, oay, oao
        if lower.contains("uyê") {
            if let idx = lower.range(of: "uyê")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 2 // tone on ê
            }
        }
        if lower.contains("oai") || lower.contains("oay") || lower.contains("oao") {
            if let idx = lower.range(of: "oa")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 1 // tone on a
            }
        }
        
        // Rule 9-10: uy, oa, oe
        if lower.contains("uy") {
            if let idx = lower.range(of: "uy")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 1 // tone on y
            }
        }
        if lower.contains("oa") {
            if let idx = lower.range(of: "oa")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 1 // tone on a
            }
        }
        if lower.contains("oe") {
            if let idx = lower.range(of: "oe")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 1 // tone on e
            }
        }
        
        // Rule 11: ia, ua, ưa
        if lower.contains("ia") || lower.contains("ua") || lower.contains("ưa") {
            return 0 // tone on first vowel
        }
        
        // Special case for uyu
        if lower.contains("uyu") {
            if let idx = lower.range(of: "uyu")?.lowerBound {
                let d = lower.distance(from: lower.startIndex, to: idx)
                return d + 1 // tone on y
            }
        }
        
        // Rule 12: general case
        if coda.isEmpty {
            return 0 // first vowel
        } else {
            return 1 // second vowel
        }
    }
    
    private static func applyToneToChar(_ char: Character, tone: Tone) -> Character {
        let isUpper = char.isUppercase
        let lookupChar = isUpper ? Character(String(char).lowercased()) : char
        
        guard let forms = toneMap[lookupChar] else {
            return char // Not a vowel we can tone-map
        }
        
        let index = tone.rawValue
        guard index < forms.count else {
            return char
        }
        
        let resultChar = forms[index]
        return isUpper ? Character(String(resultChar).uppercased()) : resultChar
    }
}
