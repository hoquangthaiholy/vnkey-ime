import Foundation

public enum InputMethodType: String {
    case telex = "telex"
    case vni = "vni"
}

public enum CharsetType: String {
    case unicode = "unicode"
    case vniWindows = "vniWindows"
    case tcvn3 = "tcvn3"
}

public struct Preferences {
    public static var shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isNewToneStyle = "isNewToneStyle"
        static let showSuggestions = "showSuggestions"
        static let inputMethod = "inputMethod"
        static let charset = "charset"
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
    
    public var charset: CharsetType {
        get {
            guard let str = defaults.string(forKey: Keys.charset), let charset = CharsetType(rawValue: str) else {
                return .unicode
            }
            return charset
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.charset)
        }
    }
}
