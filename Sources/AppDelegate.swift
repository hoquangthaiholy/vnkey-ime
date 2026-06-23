import Cocoa
import InputMethodKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    var candidatesWindow: IMKCandidates?
    
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
}
