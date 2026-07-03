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

    /// When enabled, the underline shown under text being composed is drawn as a
    /// dotted line instead of solid — macOS gives IMEs no way to set an exact
    /// stroke width, so a dotted pattern is the lightest-looking style available.
    public var reduceUnderlineThickness: Bool {
        get {
            if defaults.object(forKey: Keys.reduceUnderlineThickness) == nil {
                return false // default to the normal solid underline
            }
            return defaults.bool(forKey: Keys.reduceUnderlineThickness)
        }
        set {
            defaults.set(newValue, forKey: Keys.reduceUnderlineThickness)
        }
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
