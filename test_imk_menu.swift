import Cocoa
import InputMethodKit

class MyController: IMKInputController {
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
}
