import Foundation
struct Preferences {
    static var shared = Preferences()
    var defaults = UserDefaults.standard
    var showSuggestions: Bool {
        get { return defaults.bool(forKey: "test_show_suggestions") }
        set { defaults.set(newValue, forKey: "test_show_suggestions") }
    }
}
UserDefaults.standard.set(false, forKey: "test_show_suggestions")
Preferences.shared.showSuggestions.toggle()
print(Preferences.shared.showSuggestions)
