import Foundation

public enum InputMethodType: String {
    case telex = "telex"
    case simpleTelex = "simpleTelex"
    case simpleTelex2 = "simpleTelex2"
    case vni = "vni"
}

public enum CharsetType: String {
    case unicode = "unicode"
    case unicodeComposed = "unicodeComposed"
    case vniWindows = "vniWindows"
    case tcvn3 = "tcvn3"
    case viqr = "viqr"
    case vps = "vps"
    case vniMac = "vniMac"
    case bkhcm1 = "bkhcm1"
    case bkhcm2 = "bkhcm2"
    case cp1258 = "cp1258"
}

public struct Preferences {
    public static var shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isNewToneStyle = "isNewToneStyle"
        static let showSuggestions = "showSuggestions"
        static let inputMethod = "inputMethod"
        static let charset = "charset"
        static let enableEnglishFSM = "enableEnglishFSM"
        static let enableProgrammingFSM = "enableProgrammingFSM"
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
    
    public var enableEnglishFSM: Bool {
        get {
            if defaults.object(forKey: Keys.enableEnglishFSM) == nil {
                return true // default to enabled
            }
            return defaults.bool(forKey: Keys.enableEnglishFSM)
        }
        set {
            defaults.set(newValue, forKey: Keys.enableEnglishFSM)
        }
    }
    
    public var enableProgrammingFSM: Bool {
        get {
            if defaults.object(forKey: Keys.enableProgrammingFSM) == nil {
                return true // default to enabled
            }
            return defaults.bool(forKey: Keys.enableProgrammingFSM)
        }
        set {
            defaults.set(newValue, forKey: Keys.enableProgrammingFSM)
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
