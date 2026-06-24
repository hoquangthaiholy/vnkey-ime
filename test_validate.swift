import Cocoa

class MyController: NSResponder, NSMenuItemValidation {
    @objc func toggleSuggestions(_ sender: Any?) {}
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
}
let c = MyController()
let m = NSMenuItem(title: "Test", action: #selector(MyController.toggleSuggestions(_:)), keyEquivalent: "")
print(c.responds(to: m.action))
