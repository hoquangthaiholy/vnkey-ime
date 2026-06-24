import Cocoa
import InputMethodKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    var candidatesWindow: IMKCandidates?

    /// The currently-active input controller.  Set/cleared by VnInputController
    /// on activateServer / deactivateServer so we always have the right instance.
    weak var currentController: VnInputController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ahtstudio.inputmethod.VnKey"
        let connectionName = bundleID + "_Connection"

        // Initialize the IMKServer
        server = IMKServer(name: connectionName, bundleIdentifier: bundleID)

        // Initialize the candidate window (Single Row or Scrolling Grid)
        candidatesWindow = IMKCandidates(
            server: server,
            panelType: kIMKSingleRowSteppingCandidatePanel,
            styleType: kIMKMain
        )

        if let candidatesWindow = candidatesWindow {
            let layout = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            candidatesWindow.setSelectionKeysKeylayout(layout)

            // keycodes for 1, 2, 3, 4, 5
            let selectionKeys: [NSNumber] = [18, 19, 20, 21, 23]
            candidatesWindow.setSelectionKeys(selectionKeys)

            // Set candidate window level to show on top of Spotlight
            let level = Int(NSWindow.Level.statusBar.rawValue)
            (candidatesWindow as AnyObject).setWindowLevel?(level)
        }

        // Programmatically register ourselves as a system input source
        registerSelf()

        // Install our in-process NSStatusItem menu.
        // On macOS 26+, IMKServer's NSConnection is broken so NSMenuItem actions
        // from the IMK menu() never fire in this process. The status-item menu
        // bypasses that entirely — all clicks are dispatched locally.
        StatusMenuController.shared.setup()

        NSLog("VnKey Server started. Connection name: \(connectionName), Bundle ID: \(bundleID)")
    }

    private func registerSelf() {
        let bundlePath = Bundle.main.bundlePath
        let url = NSURL(fileURLWithPath: bundlePath)

        let status = TISRegisterInputSource(url)
        if status == noErr {
            NSLog("VnKey registered successfully as input source at \(bundlePath)")
        } else {
            NSLog("VnKey registration returned status \(status)")
        }
    }

    // MARK: - Menu actions (target for all IMK menu items)
    //
    // AppDelegate lives for the entire process lifetime, so IMK can reliably
    // route XPC-delivered menu-item actions to it.  Each method simply
    // forwards to the currently-active VnInputController.

    @objc func setInputMethod(_ sender: NSMenuItem) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate setInputMethod tag=\(sender.tag)")
        currentController?.setInputMethod(sender)
    }

    @objc func setCharset(_ sender: NSMenuItem) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate setCharset tag=\(sender.tag)")
        currentController?.setCharset(sender)
    }

    @objc func setNewToneStyle(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate setNewToneStyle")
        currentController?.setNewToneStyle(sender)
    }

    @objc func setOldToneStyle(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate setOldToneStyle")
        currentController?.setOldToneStyle(sender)
    }

    @objc func toggleSuggestions(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate toggleSuggestions")
        currentController?.toggleSuggestions(sender)
    }

    @objc func toggleEnglishFSM(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate toggleEnglishFSM")
        currentController?.toggleEnglishFSM(sender)
    }

    @objc func toggleProgrammingFSM(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG AppDelegate toggleProgrammingFSM")
        currentController?.toggleProgrammingFSM(sender)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return currentController?.validateMenuItem(menuItem) ?? true
    }
}
