import Cocoa
import InputMethodKit

class MyController: IMKInputController, NSMenuItemValidation {
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
}
