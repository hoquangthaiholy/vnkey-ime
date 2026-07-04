import Cocoa
import InputMethodKit

@objc(VnInputController)
class VnInputController: IMKInputController {

    /// Virtual keycode for the Space bar — used by the ⌘⇧Space language-toggle shortcut.
    private static let toggleLanguageKeyCode: UInt16 = 49

    var rawBuffer = ""

    /// Bundle identifier of the client app last seen in activateServer/handle —
    /// used to look up/record its remembered language under perAppLanguageMemory.
    /// StatusMenuController reads this (via AppDelegate.currentController) since
    /// its language-toggle menu item has no direct IMKTextInput client of its own.
    var lastClientBundleID: String?

    /// The last word committed to the client, used as context for next-word
    /// prediction (see NextWordPredictor). Lowercase, trimmed.
    private var lastCommittedWord = ""

    /// Predicted next words offered right after a word is committed, before
    /// the user has typed anything for the next word yet. Cleared as soon as
    /// typing starts so it doesn't linger and get confused with normal
    /// prefix-completion suggestions.
    private var pendingNextWordSuggestions: [String] = []

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

        // Global shortcut (⌘⇧Space) toggles Vietnamese/English mode, regardless of
        // which mode is currently active — checked before the passthrough below so
        // it still works while in English mode.
        if event.keyCode == Self.toggleLanguageKeyCode &&
           event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
            commitComposition(client)
            Preferences.shared.isVietnameseMode.toggle()
            rememberCurrentLanguage(for: client)
            // IMKit always invokes handle(_:client:) on the main thread, so this is safe.
            MainActor.assumeIsolated {
                StatusMenuController.shared.refresh()
            }
            return true
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
            // rawBuffer is empty but a next-word preview may still be marked
            // (see offerNextWordPredictions) — dismiss it instead of leaving a
            // dangling marked-text session the client never gets to clear.
            if !pendingNextWordSuggestions.isEmpty {
                clearComposition(client)
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
                        let suggestions = currentSuggestions()
                        if !suggestions.isEmpty {
                            var index = candidatesWindow.selectedCandidate()
                            if index < 0 || index >= suggestions.count {
                                index = 0
                            }
                            let selected = suggestions[index]
                            client.insertText(selected, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
                            recordCommittedWord(selected)
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

                // A space must always end the word as typed and trigger next-word
                // prediction — handled explicitly here (same as Tab/Enter above),
                // ahead of the generic handleKeyboardEvent() call below, since that
                // undocumented candidate-panel method may otherwise swallow the space
                // itself (e.g. treating it as a confirm/selection key) and prevent
                // our own space handling in the word-breaker section from ever running.
                if char == " " {
                    commitComposition(client)
                    offerNextWordPredictions(client: client)
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
                // Only offer a next-word prediction after a plain space — a word
                // followed by punctuation (comma, period...) is usually a clause/
                // sentence boundary, where the bigram context is much less reliable.
                if char == " " {
                    offerNextWordPredictions(client: client)
                }
                // Returning false lets the application receive and handle the space/punctuation natively
                return false
            }
            // rawBuffer is empty but a next-word preview may still be marked —
            // dismiss it before letting the client handle this key natively.
            if !pendingNextWordSuggestions.isEmpty {
                clearComposition(client)
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
            recordCommittedWord(processed)
            rawBuffer = ""
            hideCandidates()
        }
    }

    // MARK: - Next-word prediction

    /// Learns the (previous word -> this word) transition and shifts the
    /// "previous word" context forward. Called from every path that commits a
    /// word to the client (typing + space/punctuation, Tab-confirm, candidate click).
    private func recordCommittedWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !lastCommittedWord.isEmpty {
            NextWordPredictor.shared.recordTransition(from: lastCommittedWord, to: trimmed)
        }
        lastCommittedWord = trimmed
    }

    /// Proactively surfaces predicted next words in the candidate window right
    /// after a word is committed — before the user has typed anything yet.
    private func offerNextWordPredictions(client: IMKTextInput) {
        guard Preferences.shared.showSuggestions else { return }
        let predicted = NextWordPredictor.shared.predictNextWords(after: lastCommittedWord)
        guard !predicted.isEmpty else { return }
        pendingNextWordSuggestions = predicted
        // Confirmed (via logging + direct visual testing) that neither an empty
        // nor a real, visible marked-text preview renders here — candidates()/
        // showCandidates() both fire correctly but nothing ever appears.
        // Root cause: this call happens in the same synchronous pass as
        // commitComposition's insertText just above it, and the client only
        // applies one text-mutating UI update per keyDown-handling turn. Defer to
        // the next run-loop iteration so it lands in its own turn instead.
        let preview = predicted[0]
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.pendingNextWordSuggestions == predicted else { return }
            let markedString = NSAttributedString(string: preview, attributes: Self.underlineAttributes)
            client.setMarkedText(markedString, selectionRange: NSMakeRange(preview.utf16.count, 0), replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            self.showCandidates()
        }
    }

    /// Single source of truth for "what should the candidate window show right
    /// now": predicted next words while nothing has been typed yet for the
    /// next word, or normal dictionary prefix-completion once typing starts.
    private func currentSuggestions() -> [String] {
        if rawBuffer.isEmpty {
            return pendingNextWordSuggestions
        }
        let processed = VnEngine.process(raw: rawBuffer, method: currentMethod, isNewToneStyle: Preferences.shared.isNewToneStyle)
        return autocomplete.getSuggestions(prefix: processed)
    }

    // Updates the composition marking inline
    func updateComposition(_ client: IMKTextInput) {
        // Typing has started on the next word — the proactive prediction no
        // longer applies, fall back to completing what's actually being typed.
        pendingNextWordSuggestions = []

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
    // exact stroke width, so fading the color further is the only way to make it
    // read as lighter — a dotted pattern was tried but renders *more* prominent,
    // not less, since each dot needs enough size/spacing to stay visible.
    //
    // NSColor.tertiaryLabelColor already has a fairly low built-in alpha
    // (~0.38-0.4 on macOS). withAlphaComponent *replaces* that value rather than
    // scaling it, so the "reduced" alpha must be picked well below tertiary's own
    // baseline — otherwise the "reduced" state ends up more opaque, not less.
    private static var underlineAttributes: [NSAttributedString.Key: Any] {
        let color = Preferences.shared.reduceUnderlineThickness
            ? NSColor.tertiaryLabelColor.withAlphaComponent(0.15)
            : NSColor.tertiaryLabelColor
        return [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: color
        ]
    }

    override func activateServer(_ sender: Any!) {
        // Register this instance as the active controller in AppDelegate
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.currentController = self
        }
        if let client = sender as? IMKTextInput {
            applyPerAppLanguageMemory(for: client)
        }
        NSLog("VNKEY_MENU_DEBUG activateServer – registered controller in AppDelegate")
        super.activateServer(sender)
    }

    // MARK: - Per-app language memory

    /// Called when a client app activates this input controller (i.e. the user
    /// switched into that app). If perAppLanguageMemory is on and we've recorded
    /// a mode for this app before, restore it — otherwise leave the current
    /// mode alone (so a never-seen app just keeps whatever was already active).
    private func applyPerAppLanguageMemory(for client: IMKTextInput) {
        guard let bundleID = client.bundleIdentifier() else { return }
        lastClientBundleID = bundleID

        guard Preferences.shared.perAppLanguageMemory else { return }
        if let remembered = Preferences.shared.rememberedLanguageMode(forBundleID: bundleID),
           remembered != Preferences.shared.isVietnameseMode {
            Preferences.shared.isVietnameseMode = remembered
            MainActor.assumeIsolated {
                StatusMenuController.shared.refresh()
            }
        }
    }

    /// Records whatever the language mode is right now against the given client's
    /// app — call this immediately after every user-initiated language toggle.
    private func rememberCurrentLanguage(for client: IMKTextInput) {
        lastClientBundleID = client.bundleIdentifier()
        guard Preferences.shared.perAppLanguageMemory, let bundleID = lastClientBundleID else { return }
        Preferences.shared.rememberLanguageMode(Preferences.shared.isVietnameseMode, forBundleID: bundleID)
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = client() {
            commitComposition(client)
        }
        rawBuffer = ""
        hideCandidates()
        // Next-word context shouldn't leak across an app switch.
        lastCommittedWord = ""
        pendingNextWordSuggestions = []
        super.deactivateServer(sender)
    }

    override func cancelComposition() {
        rawBuffer = ""
        pendingNextWordSuggestions = []
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
        pendingNextWordSuggestions = []
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
        return currentSuggestions()
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
        recordCommittedWord(selected.string)
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
        case 403:
            Preferences.shared.perAppLanguageMemory.toggle()
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
