import Cocoa
import InputMethodKit

@objc(VnInputController)
class VnInputController: IMKInputController {
    
    var rawBuffer = ""
    var currentMethod: InputMethod = .telex
    
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
        
        // If there is an active text selection in the client application, clear our composition buffer
        let selectedRange = client.selectedRange()
        if selectedRange.location != NSNotFound && selectedRange.length > 0 {
            rawBuffer = ""
            hideCandidates()
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
                    let processed = VnEngine.process(raw: rawBuffer, method: currentMethod)
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
            let processed = VnEngine.process(raw: rawBuffer, method: currentMethod)
            client.insertText(processed, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            rawBuffer = ""
            hideCandidates()
        }
    }
    
    // Updates the composition marking inline
    func updateComposition(_ client: IMKTextInput) {
        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.clear
        ]
        let markedString = NSAttributedString(string: processed, attributes: attributes)
        
        client.setMarkedText(
            markedString,
            selectionRange: NSMakeRange(processed.utf16.count, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound)
        )
        
        // Update candidates window with suggestions
        let suggestions = autocomplete.getSuggestions(prefix: processed)
        if !suggestions.isEmpty {
            showCandidates()
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
        if let modeString = value as? String {
            NSLog("VnInputController switching mode to: \(modeString)")
            if modeString.lowercased().contains("telex") {
                currentMethod = .telex
            } else if modeString.lowercased().contains("vni") {
                currentMethod = .vni
            }
        }
        super.setValue(value, forTag: tag, client: sender)
    }
    
    // MARK: - Autocomplete Candidates Delegates
    
    override func candidates(_ sender: Any!) -> [Any]! {
        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod)
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
}

// Protocol to expose the private/undocumented handleKeyboardEvent method on IMKCandidates to the Swift compiler
@objc protocol IMKCandidatesPrivate {
    @objc(handleKeyboardEvent:)
    func handleKeyboardEvent(_ event: NSEvent?) -> Bool
    
    @objc(setWindowLevel:)
    func setWindowLevel(_ level: Int)
}
