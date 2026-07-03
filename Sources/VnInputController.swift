import Cocoa
import InputMethodKit

@objc(VnInputController)
class VnInputController: IMKInputController {

    var rawBuffer = ""
    var currentMethod: InputMethod {
        switch Preferences.shared.inputMethod {
        case .vni: return .vni
        case .telex: return .telex
        }
    }

    private func debugMenu(_ message: String) {
        #if DEBUG
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
        #endif
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

        // Language mode: in English mode, act as a pure passthrough — never buffer
        // or transform keystrokes, let the client application handle them natively.
        if !Preferences.shared.isVietnameseMode {
            if !rawBuffer.isEmpty {
                commitComposition(client)
            }
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
                            client.insertText(selected, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
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
            client.insertText(processed, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            rawBuffer = ""
            hideCandidates()
        }
    }

    // Updates the composition marking inline
    func updateComposition(_ client: IMKTextInput) {
        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod, isNewToneStyle: Preferences.shared.isNewToneStyle)

        let markedString = NSAttributedString(string: processed, attributes: Self.underlineAttributes)

        client.setMarkedText(
            markedString,
            selectionRange: NSMakeRange(processed.utf16.count, 0),
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
        return Self.underlineAttributes
    }

    // NSTextView-based apps (TextEdit, Notes, Mail) always draw their own default
    // underline under marked/composing text as a system-level "IME in progress"
    // indicator — it cannot be suppressed. Explicitly requesting a thin, faint
    // underline instead of leaving it unset replaces that (heavier) default with
    // the least obtrusive style we can control. macOS gives IMEs no way to set an
    // exact stroke width, so a dotted pattern is the lightest look available beyond that.
    private static var underlineAttributes: [NSAttributedString.Key: Any] {
        var style: NSUnderlineStyle = .single
        if Preferences.shared.reduceUnderlineThickness {
            style.insert(.patternDot)
        }
        return [
            .underlineStyle: style.rawValue,
            .underlineColor: NSColor.tertiaryLabelColor
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
        if setInputMethod(forTag: tag) || setDiacriticOption(forTag: tag) || toggleAccessibilityOption(forTag: tag) {
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
        client.insertText(selected.string, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        rawBuffer = ""
        hideCandidates()
    }

    override func menu() -> NSMenu! {
        return nil
    }

    private func setInputMethod(forTag tag: Int) -> Bool {
        switch tag {
        case 101: Preferences.shared.inputMethod = .telex
        case 104: Preferences.shared.inputMethod = .vni
        default: return false
        }
        NSLog("VNKEY_MENU_DEBUG inputMethod now \(Preferences.shared.inputMethod.rawValue)")
        debugMenu("inputMethod now \(Preferences.shared.inputMethod.rawValue)")
        return true
    }

    private func setDiacriticOption(forTag tag: Int) -> Bool {
        switch tag {
        case 301: Preferences.shared.isNewToneStyle = true
        case 302: Preferences.shared.isNewToneStyle = false
        case 303: Preferences.shared.telexWAnywhere.toggle()
        case 304: Preferences.shared.telexBrackets.toggle()
        case 305: Preferences.shared.restoreMistypedVietnamese.toggle()
        default: return false
        }
        NSLog("VNKEY_MENU_DEBUG diacritic option tag \(tag) handled")
        debugMenu("diacritic option tag \(tag) handled")
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
            Preferences.shared.reduceUnderlineThickness.toggle()
        default:
            return false
        }
        NSLog("VNKEY_MENU_DEBUG accessibility tag \(tag) handled")
        debugMenu("accessibility tag \(tag) handled")
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
