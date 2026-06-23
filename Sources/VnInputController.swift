import Cocoa
import InputMethodKit

@objc(VnInputController)
class VnInputController: IMKInputController {
    
    var rawBuffer = ""
    var currentMethod: InputMethod {
        return Preferences.shared.inputMethod == .vni ? .vni : .telex
    }
    
    // Lazy initialization of Autocomplete helper
    lazy var autocomplete: Autocomplete = Autocomplete()
    
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
        // We clear the rawBuffer and hide candidates so we don't interfere with the shortcut.
        if event.modifierFlags.contains(.command) ||
           event.modifierFlags.contains(.control) ||
           event.modifierFlags.contains(.option) {
            rawBuffer = ""
            hideCandidates()
            return false
        }
        
        // If there is an active text selection in the client application, clear our composition buffer.
        // We only perform this synchronous IPC check if rawBuffer is not empty to eliminate typing latency at word start.
        if !rawBuffer.isEmpty {
            let selectedRange = client.selectedRange()
            if selectedRange.location != NSNotFound && selectedRange.length > 0 {
                rawBuffer = ""
                hideCandidates()
            }
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
        
        // 3. Handle Space, Return, Tab, Punctuation (Word Breakers)
        if char.isWhitespace || char.isNewline || char == "\t" || isPunctuation(char) {
            if !rawBuffer.isEmpty {
                commitComposition(client)
                // Returning false lets the application receive and handle the space/punctuation natively
                return false
            }
            return false
        }
        
        // 4. Handle Alphanumeric characters
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
    func commitComposition(_ client: IMKTextInput) {
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
        // We no longer switch method based on system OS tag since we merged into one Input Source.
        // We rely on our own Preferences.shared.inputMethod instead.
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
        let menu = NSMenu(title: "Tuỳ chọn")
        
        let methodMenuItem = NSMenuItem(title: "Kiểu gõ", action: nil, keyEquivalent: "")
        let methodMenu = NSMenu(title: "Kiểu gõ")
        
        let telexItem = NSMenuItem(title: "Telex", action: #selector(setMethodTelex(_:)), keyEquivalent: "")
        telexItem.target = self
        telexItem.state = Preferences.shared.inputMethod == .telex ? .on : .off
        methodMenu.addItem(telexItem)
        
        let vniItem = NSMenuItem(title: "VNI", action: #selector(setMethodVNI(_:)), keyEquivalent: "")
        vniItem.target = self
        vniItem.state = Preferences.shared.inputMethod == .vni ? .on : .off
        methodMenu.addItem(vniItem)
        
        methodMenuItem.submenu = methodMenu
        menu.addItem(methodMenuItem)
        
        menu.addItem(NSMenuItem.separator())

        let charsetMenuItem = NSMenuItem(title: "Bảng mã", action: nil, keyEquivalent: "")
        let charsetMenu = NSMenu(title: "Bảng mã")
        
        let charsetUnicode = NSMenuItem(title: "Unicode", action: #selector(setCharsetUnicode(_:)), keyEquivalent: "")
        charsetUnicode.target = self
        charsetUnicode.state = Preferences.shared.charset == .unicode ? .on : .off
        charsetMenu.addItem(charsetUnicode)
        
        let charsetVNI = NSMenuItem(title: "VNI Windows", action: #selector(setCharsetVNIWindows(_:)), keyEquivalent: "")
        charsetVNI.target = self
        charsetVNI.state = Preferences.shared.charset == .vniWindows ? .on : .off
        charsetMenu.addItem(charsetVNI)
        
        let charsetTCVN3 = NSMenuItem(title: "TCVN3 (ABC)", action: #selector(setCharsetTCVN3(_:)), keyEquivalent: "")
        charsetTCVN3.target = self
        charsetTCVN3.state = Preferences.shared.charset == .tcvn3 ? .on : .off
        charsetMenu.addItem(charsetTCVN3)
        
        charsetMenuItem.submenu = charsetMenu
        menu.addItem(charsetMenuItem)
        
        menu.addItem(NSMenuItem.separator())

        let toneMenuItem = NSMenuItem(title: "Bỏ dấu", action: nil, keyEquivalent: "")
        let toneMenu = NSMenu(title: "Bỏ dấu")
        
        let newStyleItem = NSMenuItem(title: "Kiểu mới (oà, uý)", action: #selector(setNewToneStyle(_:)), keyEquivalent: "")
        newStyleItem.target = self
        newStyleItem.state = Preferences.shared.isNewToneStyle ? .on : .off
        toneMenu.addItem(newStyleItem)
        
        let oldStyleItem = NSMenuItem(title: "Kiểu cũ (òa, úy)", action: #selector(setOldToneStyle(_:)), keyEquivalent: "")
        oldStyleItem.target = self
        oldStyleItem.state = !Preferences.shared.isNewToneStyle ? .on : .off
        toneMenu.addItem(oldStyleItem)
        
        toneMenuItem.submenu = toneMenu
        menu.addItem(toneMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let accessibilityMenuItem = NSMenuItem(title: "Trợ năng", action: nil, keyEquivalent: "")
        let accessibilityMenu = NSMenu(title: "Trợ năng")
        
        let suggestionsItem = NSMenuItem(title: "Hiện gợi ý từ", action: #selector(toggleSuggestions(_:)), keyEquivalent: "")
        suggestionsItem.target = self
        suggestionsItem.state = Preferences.shared.showSuggestions ? .on : .off
        accessibilityMenu.addItem(suggestionsItem)
        
        accessibilityMenuItem.submenu = accessibilityMenu
        menu.addItem(accessibilityMenuItem)
        
        return menu
    }
    
    @objc func setMethodTelex(_ sender: Any?) {
        Preferences.shared.inputMethod = .telex
    }
    
    @objc func setMethodVNI(_ sender: Any?) {
        Preferences.shared.inputMethod = .vni
    }
    
    @objc func setCharsetUnicode(_ sender: Any?) {
        Preferences.shared.charset = .unicode
    }
    
    @objc func setCharsetVNIWindows(_ sender: Any?) {
        Preferences.shared.charset = .vniWindows
    }
    
    @objc func setCharsetTCVN3(_ sender: Any?) {
        Preferences.shared.charset = .tcvn3
    }
    
    @objc func setNewToneStyle(_ sender: Any?) {
        NSLog("VnInputController setNewToneStyle")
        Preferences.shared.isNewToneStyle = true
    }
    
    @objc func setOldToneStyle(_ sender: Any?) {
        NSLog("VnInputController setOldToneStyle")
        Preferences.shared.isNewToneStyle = false
    }
    
    @objc func toggleSuggestions(_ sender: Any?) {
        NSLog("VnInputController toggleSuggestions called")
        Preferences.shared.showSuggestions.toggle()
        if !Preferences.shared.showSuggestions {
            hideCandidates()
        }
    }
}

// Protocol to expose the private/undocumented handleKeyboardEvent method on IMKCandidates to the Swift compiler
@objc protocol IMKCandidatesPrivate {
    @objc(handleKeyboardEvent:)
    func handleKeyboardEvent(_ event: NSEvent?) -> Bool
    
    @objc(setWindowLevel:)
    func setWindowLevel(_ level: Int)
}
