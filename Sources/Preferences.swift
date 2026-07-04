import Foundation

public enum InputMethodType: String {
    case telex = "telex"
    case vni = "vni"
}

public struct Preferences {
    public static var shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isNewToneStyle = "isNewToneStyle"
        static let showSuggestions = "showSuggestions"
        static let inputMethod = "inputMethod"
        static let restoreMistypedVietnamese = "restoreMistypedVietnamese"
        static let isVietnameseMode = "isVietnameseMode"
        static let telexWAnywhere = "telexWAnywhere"
        static let telexBrackets = "telexBrackets"
        static let reduceUnderlineThickness = "reduceUnderlineThickness"
        static let perAppLanguageMemory = "perAppLanguageMemory"
        static let perAppLanguageMap = "perAppLanguageMap"
    }

    public var isVietnameseMode: Bool {
        get {
            if defaults.object(forKey: Keys.isVietnameseMode) == nil {
                return true // default to Vietnamese typing
            }
            return defaults.bool(forKey: Keys.isVietnameseMode)
        }
        set {
            defaults.set(newValue, forKey: Keys.isVietnameseMode)
        }
    }
    
    public var isNewToneStyle: Bool {
        get {
            if defaults.object(forKey: Keys.isNewToneStyle) == nil {
                return false // default to old style
            }
            return defaults.bool(forKey: Keys.isNewToneStyle)
        }
        set {
            defaults.set(newValue, forKey: Keys.isNewToneStyle)
        }
    }
    
    public var showSuggestions: Bool {
        get {
            if defaults.object(forKey: Keys.showSuggestions) == nil {
                return false // default to hide
            }
            return defaults.bool(forKey: Keys.showSuggestions)
        }
        set {
            defaults.set(newValue, forKey: Keys.showSuggestions)
        }
    }
    
    /// When enabled, a typed sequence that doesn't form a valid Vietnamese syllable
    /// (e.g. an English word mistakenly transformed by the Telex/VNI FSM) is restored
    /// to what was actually typed instead of being kept as a garbled Vietnamese word.
    public var restoreMistypedVietnamese: Bool {
        get {
            if defaults.object(forKey: Keys.restoreMistypedVietnamese) == nil {
                return true // default to enabled
            }
            return defaults.bool(forKey: Keys.restoreMistypedVietnamese)
        }
        set {
            defaults.set(newValue, forKey: Keys.restoreMistypedVietnamese)
        }
    }
    
    /// When enabled, Telex's 'w' key produces 'ư' even with no vowel typed yet
    /// (e.g. "w" -> "ư"). Off by default — standard Telex only lets 'w' convert
    /// an existing vowel (e.g. "tuwf" -> "từ"); this is an opt-in shortcut.
    public var telexWAnywhere: Bool {
        get {
            if defaults.object(forKey: Keys.telexWAnywhere) == nil {
                return false // off by default — not part of standard Telex
            }
            return defaults.bool(forKey: Keys.telexWAnywhere)
        }
        set {
            defaults.set(newValue, forKey: Keys.telexWAnywhere)
        }
    }

    /// When enabled, Telex's '[' and ']' keys type 'ơ'/'ư' directly. Off by
    /// default — not part of standard Telex; this is an opt-in shortcut.
    public var telexBrackets: Bool {
        get {
            if defaults.object(forKey: Keys.telexBrackets) == nil {
                return false // off by default — not part of standard Telex
            }
            return defaults.bool(forKey: Keys.telexBrackets)
        }
        set {
            defaults.set(newValue, forKey: Keys.telexBrackets)
        }
    }

    /// When enabled, the underline shown under text being composed is drawn more
    /// faded (lower opacity) — macOS gives IMEs no way to set an exact stroke
    /// width, so a fainter color is the closest we can get to "thinner".
    public var reduceUnderlineThickness: Bool {
        get {
            if defaults.object(forKey: Keys.reduceUnderlineThickness) == nil {
                return false // default to the normal underline opacity
            }
            return defaults.bool(forKey: Keys.reduceUnderlineThickness)
        }
        set {
            defaults.set(newValue, forKey: Keys.reduceUnderlineThickness)
        }
    }

    /// When enabled, VnKey remembers the last Vietnamese/English mode used in
    /// each application (keyed by bundle identifier) and automatically restores
    /// it when you switch back to that app — e.g. Xcode/Terminal stay in English
    /// and Mail/Notes stay in Vietnamese without manually toggling each time.
    public var perAppLanguageMemory: Bool {
        get {
            if defaults.object(forKey: Keys.perAppLanguageMemory) == nil {
                return false // opt-in: off by default, since auto-switching is a behavior change
            }
            return defaults.bool(forKey: Keys.perAppLanguageMemory)
        }
        set {
            defaults.set(newValue, forKey: Keys.perAppLanguageMemory)
        }
    }

    /// The remembered Vietnamese/English mode for a given app, if one was ever recorded.
    public func rememberedLanguageMode(forBundleID bundleID: String) -> Bool? {
        guard let map = defaults.dictionary(forKey: Keys.perAppLanguageMap) as? [String: Bool] else {
            return nil
        }
        return map[bundleID]
    }

    /// Records the current Vietnamese/English mode against a given app's bundle identifier.
    public func rememberLanguageMode(_ isVietnamese: Bool, forBundleID bundleID: String) {
        var map = (defaults.dictionary(forKey: Keys.perAppLanguageMap) as? [String: Bool]) ?? [:]
        map[bundleID] = isVietnamese
        defaults.set(map, forKey: Keys.perAppLanguageMap)
    }

    public var inputMethod: InputMethodType {
        get {
            guard let str = defaults.string(forKey: Keys.inputMethod), let method = InputMethodType(rawValue: str) else {
                return .telex
            }
            return method
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.inputMethod)
        }
    }
}
