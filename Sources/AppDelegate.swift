import Cocoa
import InputMethodKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    var candidatesWindow: IMKCandidates?

    /// The currently-active input controller.  Set/cleared by VnInputController
    /// on activateServer / deactivateServer so we always have the right instance.
    weak var currentController: VnInputController?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm Autocomplete dictionary on a background thread so it doesn't freeze the first keystroke
        DispatchQueue.global(qos: .utility).async {
            _ = Autocomplete.shared
        }
        
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

        registerGlobalToggleHotKey()

        NSLog("VnKey Server started. Connection name: \(connectionName), Bundle ID: \(bundleID)")
    }

    // MARK: - Global ⌘⇧Space language toggle

    /// Cmd-modified keystrokes are generally matched against the app's menu
    /// bar / responder chain as a shortcut *before* ever being offered to an
    /// input method — VnInputController.handle() simply never sees them in
    /// many apps (Terminal included), which just beeps for the unclaimed
    /// shortcut instead of toggling the language. Carbon's RegisterEventHotKey
    /// is the standard, permission-free way to claim a key combination at the
    /// system level so it's consumed before any app (or its beep) sees it —
    /// this is how other input methods implement global toggle hotkeys too.
    private func registerGlobalToggleHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetEventDispatcherTarget(), { _, eventRef, userData in
            guard let userData = userData, let eventRef = eventRef else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.id == 1 else { return noErr }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    appDelegate.toggleVietnameseModeGlobally()
                }
            }
            return noErr
        }, 1, &eventType, selfPtr, &hotKeyEventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x564E_4B59), id: 1) // 'VNKY'
        let keyCodeSpace: UInt32 = 49
        let status = RegisterEventHotKey(keyCodeSpace, UInt32(cmdKey | shiftKey), hotKeyID,
                                          GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("VnKey: failed to register global ⌘⇧Space hotkey, status=\(status)")
        }
    }

    @MainActor
    private func toggleVietnameseModeGlobally() {
        if let controller = currentController {
            controller.handleGlobalLanguageToggle()
        } else {
            Preferences.shared.isVietnameseMode.toggle()
            StatusMenuController.shared.refresh()
        }
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
