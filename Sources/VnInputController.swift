import Cocoa
import InputMethodKit

/// Singleton that receives menu-bar action messages and forwards them to the
/// currently-active VnInputController.  Using a process-level singleton as
/// the `target` of NSMenuItems lets InputMethodKit route the XPC-delivered
/// action to a real Objective-C object that is alive in our process.
@objc class MenuActionDispatcher: NSObject {
    @objc static let shared = MenuActionDispatcher()
    weak var controller: VnInputController?

    @objc func setInputMethod(_ sender: NSMenuItem) {
        controller?.setInputMethod(sender)
    }
    @objc func setCharset(_ sender: NSMenuItem) {
        controller?.setCharset(sender)
    }
    @objc func setNewToneStyle(_ sender: Any?) {
        controller?.setNewToneStyle(sender)
    }
    @objc func setOldToneStyle(_ sender: Any?) {
        controller?.setOldToneStyle(sender)
    }
    @objc func toggleSuggestions(_ sender: Any?) {
        controller?.toggleSuggestions(sender)
    }
    @objc func toggleEnglishFSM(_ sender: Any?) {
        controller?.toggleEnglishFSM(sender)
    }
    @objc func toggleProgrammingFSM(_ sender: Any?) {
        controller?.toggleProgrammingFSM(sender)
    }
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return controller?.validateMenuItem(menuItem) ?? true
    }
}

@objc(VnInputController)
class VnInputController: IMKInputController {

    var rawBuffer = ""
    var currentMethod: InputMethod {
        switch Preferences.shared.inputMethod {
        case .vni: return .vni
        case .simpleTelex: return .simpleTelex
        case .simpleTelex2: return .simpleTelex2
        case .telex: return .telex
        }
    }

    private func debugMenu(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/vnkey-menu-debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    // Use shared Autocomplete helper to avoid duplicate memory and parsing overhead
    var autocomplete: Autocomplete { return Autocomplete.shared }

    // Intercept keyboard events from the client application
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else {
            return false
        }

        // We only process Key Down events
        if event.type != .keyDown {
            return false
        }

        // Pass shortcuts (Command, Control, Option modifiers) through to the client.
        // We commit the active composition so we don't lose the word being typed.
        if event.modifierFlags.contains(.command) ||
           event.modifierFlags.contains(.control) ||
           event.modifierFlags.contains(.option) {
            commitComposition(client)
            return false
        }

        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }

        let char = characters.first!
        let keyCode = event.keyCode

        // 1. Handle Backspace (Delete) key (keyCode 51 on standard mac keyboards)
        if char == Character(UnicodeScalar(127)) || char == Character(UnicodeScalar(8)) || keyCode == 51 {
            if !rawBuffer.isEmpty {
                rawBuffer.removeLast()
                updateComposition(client)
                return true
            }
            return false
        }

        // 2. Handle Escape (cancels active buffer and hides suggestions)
        if keyCode == 53 || char == Character(UnicodeScalar(27)) {
            if !rawBuffer.isEmpty || isCandidatesVisible() {
                clearComposition(client)
                return true
            }
            return false
        }

        // Forward event to candidate window if it is visible
        if isCandidatesVisible() {
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
               let candidatesWindow = appDelegate.candidatesWindow {

                // If Tab key is pressed, confirm the highlighted candidate
                if keyCode == 48 || char == "\t" {
                    if Preferences.shared.showSuggestions {
                        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod, isNewToneStyle: Preferences.shared.isNewToneStyle)
                        let suggestions = autocomplete.getSuggestions(prefix: processed)
                        if !suggestions.isEmpty {
                            var index = candidatesWindow.selectedCandidate()
                            if index < 0 || index >= suggestions.count {
                                index = 0
                            }
                            let selected = suggestions[index]
                            let finalString = CharsetConverter.convert(selected, to: Preferences.shared.charset)
                            client.insertText(finalString, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
                            rawBuffer = ""
                            hideCandidates()
                            return true
                        }
                    }
                }

                // If Enter/Return is pressed, commit composition as-is and let application handle it natively
                if keyCode == 36 || keyCode == 76 || char == "\r" || char == "\n" {
                    commitComposition(client)
                    return false
                }

                let candidatesObj = candidatesWindow as AnyObject
                if candidatesObj.handleKeyboardEvent(event) == true {
                    return true
                }
            }
        }

        // 3. Handle Navigation keys (Arrow keys, Home, End, Page Up, Page Down)
        let navigationKeyCodes: Set<UInt16> = [115, 116, 119, 121, 123, 124, 125, 126]
        if navigationKeyCodes.contains(keyCode) {
            commitComposition(client)
            return false
        }

        // 4. Handle Space, Return, Tab, Punctuation (Word Breakers)
        if char.isWhitespace || char.isNewline || char == "\t" || isPunctuation(char) {
            if !rawBuffer.isEmpty {
                commitComposition(client)
                // Returning false lets the application receive and handle the space/punctuation natively
                return false
            }
            return false
        }

        // 5. Handle Alphanumeric characters
        if char.isLetter || char.isNumber {
            rawBuffer.append(char)
            updateComposition(client)
            return true
        }

        // Default: commit active composition and let application handle it
        commitComposition(client)
        return false
    }

    // Commits the active composition to the client
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        if !rawBuffer.isEmpty {
            let processed = VnEngine.process(raw: rawBuffer, method: currentMethod, isNewToneStyle: Preferences.shared.isNewToneStyle)
            let finalString = CharsetConverter.convert(processed, to: Preferences.shared.charset)
            client.insertText(finalString, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            rawBuffer = ""
            hideCandidates()
        }
    }

    // Updates the composition marking inline
    func updateComposition(_ client: IMKTextInput) {
        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod, isNewToneStyle: Preferences.shared.isNewToneStyle)
        let displayString = CharsetConverter.convert(processed, to: Preferences.shared.charset)

        let attributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.clear
        ]
        let markedString = NSAttributedString(string: displayString, attributes: attributes)

        client.setMarkedText(
            markedString,
            selectionRange: NSMakeRange(displayString.utf16.count, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound)
        )

        // Update candidates window with suggestions
        if Preferences.shared.showSuggestions {
            let suggestions = autocomplete.getSuggestions(prefix: processed)
            if !suggestions.isEmpty {
                showCandidates()
            } else {
                hideCandidates()
            }
        } else {
            hideCandidates()
        }
    }

    override func mark(forStyle style: Int, at range: NSRange) -> [AnyHashable : Any]! {
        return [
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
            NSAttributedString.Key.underlineColor: NSColor.clear
        ]
    }

    override func activateServer(_ sender: Any!) {
        // Register this instance as the active controller in AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.currentController = self
        }
        NSLog("VNKEY_MENU_DEBUG activateServer – registered controller in AppDelegate")
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = client() {
            commitComposition(client)
        }
        rawBuffer = ""
        hideCandidates()
        super.deactivateServer(sender)
    }

    override func cancelComposition() {
        rawBuffer = ""
        hideCandidates()
        super.cancelComposition()
    }

    // Clears/Cancels composition without inserting
    func clearComposition(_ client: IMKTextInput) {
        client.setMarkedText(
            "",
            selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound)
        )
        rawBuffer = ""
        hideCandidates()
    }

    // Helper to identify punctuation marks
    func isPunctuation(_ char: Character) -> Bool {
        let punctuationSet = CharacterSet.punctuationCharacters
        return char.unicodeScalars.allSatisfy { punctuationSet.contains($0) }
    }

    // MARK: - Input Source Mode Switching

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        NSLog("VNKEY_MENU_DEBUG setValue tag=\(tag), value=\(String(describing: value))")
        debugMenu("setValue tag=\(tag), value=\(String(describing: value))")
        if setInputMethod(forTag: tag) || setCharset(forTag: tag) || setToneStyle(forTag: tag) || toggleAccessibilityOption(forTag: tag) {
            return
        }

        super.setValue(value, forTag: tag, client: sender)
    }

    // MARK: - Autocomplete Candidates Delegates

    override func candidates(_ sender: Any!) -> [Any]! {
        if !Preferences.shared.showSuggestions { return [] }
        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod, isNewToneStyle: Preferences.shared.isNewToneStyle)
        return autocomplete.getSuggestions(prefix: processed)
    }

    func showCandidates() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate,
              let candidatesWindow = appDelegate.candidatesWindow else {
            return
        }
        candidatesWindow.update()
        candidatesWindow.show()
    }

    func hideCandidates() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate,
              let candidatesWindow = appDelegate.candidatesWindow else {
            return
        }
        candidatesWindow.hide()
    }

    func isCandidatesVisible() -> Bool {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate,
              let candidatesWindow = appDelegate.candidatesWindow else {
            return false
        }
        return candidatesWindow.isVisible()
    }



    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = client(), let selected = candidateString else { return }
        let finalString = CharsetConverter.convert(selected.string, to: Preferences.shared.charset)
        client.insertText(finalString, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        rawBuffer = ""
        hideCandidates()
    }

    override func menu() -> NSMenu! {
        return nil
    }

    @objc func setInputMethod(_ sender: NSMenuItem) {
        NSLog("VNKEY_MENU_DEBUG setInputMethod action tag=\(sender.tag)")
        debugMenu("setInputMethod action tag=\(sender.tag)")
        _ = setInputMethod(forTag: sender.tag)
    }

    @objc func setCharset(_ sender: NSMenuItem) {
        NSLog("VNKEY_MENU_DEBUG setCharset action tag=\(sender.tag)")
        debugMenu("setCharset action tag=\(sender.tag)")
        _ = setCharset(forTag: sender.tag)
    }

    @objc func setNewToneStyle(_ sender: Any?) {
        NSLog("VnInputController setNewToneStyle")
        debugMenu("setNewToneStyle action")
        Preferences.shared.isNewToneStyle = true
    }

    @objc func setOldToneStyle(_ sender: Any?) {
        NSLog("VnInputController setOldToneStyle")
        debugMenu("setOldToneStyle action")
        Preferences.shared.isNewToneStyle = false
    }

    @objc func toggleSuggestions(_ sender: Any?) {
        NSLog("VnInputController toggleSuggestions called")
        debugMenu("toggleSuggestions action")
        Preferences.shared.showSuggestions.toggle()
        if !Preferences.shared.showSuggestions {
            hideCandidates()
        }
    }

    @objc func toggleEnglishFSM(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG toggleEnglishFSM action")
        debugMenu("toggleEnglishFSM action")
        Preferences.shared.enableEnglishFSM.toggle()
    }

    @objc func toggleProgrammingFSM(_ sender: Any?) {
        NSLog("VNKEY_MENU_DEBUG toggleProgrammingFSM action")
        debugMenu("toggleProgrammingFSM action")
        Preferences.shared.enableProgrammingFSM.toggle()
    }

    private func setInputMethod(forTag tag: Int) -> Bool {
        switch tag {
        case 101: Preferences.shared.inputMethod = .telex
        case 102: Preferences.shared.inputMethod = .simpleTelex
        case 103: Preferences.shared.inputMethod = .simpleTelex2
        case 104: Preferences.shared.inputMethod = .vni
        default: return false
        }
        NSLog("VNKEY_MENU_DEBUG inputMethod now \(Preferences.shared.inputMethod.rawValue)")
        debugMenu("inputMethod now \(Preferences.shared.inputMethod.rawValue)")
        return true
    }

    private func setCharset(forTag tag: Int) -> Bool {
        switch tag {
        case 201: Preferences.shared.charset = .unicode
        case 202: Preferences.shared.charset = .unicodeComposed
        case 203: Preferences.shared.charset = .vniWindows
        case 204: Preferences.shared.charset = .tcvn3
        case 205: Preferences.shared.charset = .viqr
        case 206: Preferences.shared.charset = .vps
        case 207: Preferences.shared.charset = .vniMac
        case 208: Preferences.shared.charset = .bkhcm1
        case 209: Preferences.shared.charset = .bkhcm2
        case 210: Preferences.shared.charset = .cp1258
        default: return false
        }
        NSLog("VNKEY_MENU_DEBUG charset now \(Preferences.shared.charset.rawValue)")
        debugMenu("charset now \(Preferences.shared.charset.rawValue)")
        return true
    }

    private func setToneStyle(forTag tag: Int) -> Bool {
        switch tag {
        case 301: Preferences.shared.isNewToneStyle = true
        case 302: Preferences.shared.isNewToneStyle = false
        default: return false
        }
        NSLog("VNKEY_MENU_DEBUG isNewToneStyle now \(Preferences.shared.isNewToneStyle)")
        debugMenu("isNewToneStyle now \(Preferences.shared.isNewToneStyle)")
        return true
    }

    private func toggleAccessibilityOption(forTag tag: Int) -> Bool {
        switch tag {
        case 401:
            Preferences.shared.showSuggestions.toggle()
            if !Preferences.shared.showSuggestions {
                hideCandidates()
            }
        case 402:
            Preferences.shared.enableEnglishFSM.toggle()
        case 403:
            Preferences.shared.enableProgrammingFSM.toggle()
        default:
            return false
        }
        NSLog("VNKEY_MENU_DEBUG accessibility tag \(tag) handled")
        debugMenu("accessibility tag \(tag) handled")
        return true
    }
}

extension VnInputController: NSMenuItemValidation {
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        NSLog("VNKEY_MENU_DEBUG validate action=\(String(describing: menuItem.action)) tag=\(menuItem.tag)")
        debugMenu("validate action=\(String(describing: menuItem.action)) tag=\(menuItem.tag)")
        if menuItem.action == #selector(toggleSuggestions(_:)) {
            menuItem.state = Preferences.shared.showSuggestions ? .on : .off
        } else if menuItem.action == #selector(toggleEnglishFSM(_:)) {
            menuItem.state = Preferences.shared.enableEnglishFSM ? .on : .off
        } else if menuItem.action == #selector(toggleProgrammingFSM(_:)) {
            menuItem.state = Preferences.shared.enableProgrammingFSM ? .on : .off
        } else if menuItem.action == #selector(setNewToneStyle(_:)) {
            menuItem.state = Preferences.shared.isNewToneStyle ? .on : .off
        } else if menuItem.action == #selector(setOldToneStyle(_:)) {
            menuItem.state = !Preferences.shared.isNewToneStyle ? .on : .off
        } else if menuItem.action == #selector(setInputMethod(_:)) {
            let method: InputMethodType?
            switch menuItem.tag {
            case 101: method = .telex
            case 102: method = .simpleTelex
            case 103: method = .simpleTelex2
            case 104: method = .vni
            default: method = nil
            }
            if let m = method {
                menuItem.state = (Preferences.shared.inputMethod == m) ? .on : .off
            }
        } else if menuItem.action == #selector(setCharset(_:)) {
            let charset: CharsetType?
            switch menuItem.tag {
            case 201: charset = .unicode
            case 202: charset = .unicodeComposed
            case 203: charset = .vniWindows
            case 204: charset = .tcvn3
            case 205: charset = .viqr
            case 206: charset = .vps
            case 207: charset = .vniMac
            case 208: charset = .bkhcm1
            case 209: charset = .bkhcm2
            case 210: charset = .cp1258
            default: charset = nil
            }
            if let c = charset {
                menuItem.state = (Preferences.shared.charset == c) ? .on : .off
            }
        }
        return true
    }
}

// Protocol to expose the private/undocumented handleKeyboardEvent method on IMKCandidates to the Swift compiler
@objc protocol IMKCandidatesPrivate {
    @objc(handleKeyboardEvent:)
    func handleKeyboardEvent(_ event: NSEvent?) -> Bool

    @objc(setWindowLevel:)
    func setWindowLevel(_ level: Int)
}
