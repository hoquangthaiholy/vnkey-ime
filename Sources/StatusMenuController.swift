import Cocoa
import Carbon

/// Manages an NSStatusItem that lives entirely within the VnKey process.
///
/// On macOS 26+, IMKServer's legacy NSConnection mechanism is broken, so
/// NSMenuItem actions set on the IMK menu() result never fire in the input-method
/// process. This controller creates a real in-process menu via NSStatusItem;
/// clicking any item calls Preferences directly, no XPC involved.
@MainActor
class StatusMenuController: NSObject {
    static let shared = StatusMenuController()

    private var statusItem: NSStatusItem?

    private override init() {
        super.init()
    }

    /// The app's real icon, used for the About panel and the reset-
    /// confirmation alert. A single 512x512 PNG rather than a full multi-
    /// resolution .icns — this only ever needs to render at dialog-icon size
    /// (there's no Dock/Finder icon to serve, since VnKey is an LSUIElement
    /// agent), and the .icns's other resolutions were ~7x the size of the
    /// app's own binary for no practical benefit here.
    private static var appIcon: NSImage? {
        guard let path = Bundle.main.path(forResource: "AppIcon", ofType: "png") else { return nil }
        return NSImage(contentsOfFile: path)
    }

    // MARK: - Public API

    /// Call once from AppDelegate.applicationDidFinishLaunching to install the status item.
    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = buildMenu()
        statusItem = item
        
        // Listen for input source changes across the system via CF Distributed Notification Center
        let distributedCenter = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            distributedCenter,
            observer,
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                let controller = Unmanaged<StatusMenuController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        controller.inputSourceChanged()
                    }
                }
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
        
        // Also observe through Cocoa DistributedNotificationCenter with deliverImmediately
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        updateButton()
    }

    @objc private func applicationActivated(_ notification: Notification) {
        updateButton()
        guard Preferences.shared.perAppLanguageMemory else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else {
            return
        }
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.theodore.inputmethod.VnKey"
        if bundleID == myBundleID || bundleID == "\(myBundleID).mac" {
            return
        }
        if let remembered = Preferences.shared.rememberedLanguageMode(forBundleID: bundleID),
           remembered != Preferences.shared.isVietnameseMode {
            Preferences.shared.isVietnameseMode = remembered
            refresh()
        }
    }

    /// Rebuild the menu so check-marks reflect current Preferences.
    /// Called automatically whenever a preference changes.
    func refresh() {
        statusItem?.menu = buildMenu()
        updateButton()
    }

    @objc private func inputSourceChanged() {
        updateButton()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.updateButton()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.updateButton()
        }
    }

    private func isVnKeyActive() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.theodore.inputmethod.VnKey"
        if let idPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if id == myBundleID || id == "\(myBundleID).mac" || id.hasPrefix(myBundleID) {
                return true
            }
        }
        if let bundlePtr = TISGetInputSourceProperty(currentSource, kTISPropertyBundleID) {
            let bundleID = Unmanaged<CFString>.fromOpaque(bundlePtr).takeUnretainedValue() as String
            if bundleID == myBundleID || bundleID.hasPrefix(myBundleID) {
                return true
            }
        }
        return false
    }

    private func createIconImage(text: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let color = NSColor.black
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        // The "|" separator (e.g. "V | Telex") is drawn shorter, more faded, and
        // with extra tracking than the surrounding text so it reads as a subtle
        // divider, not a glyph.
        let separatorFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: separatorFont,
            .foregroundColor: color.withAlphaComponent(0.4),
            .baselineOffset: (font.pointSize - separatorFont.pointSize) / 2.0 + 1.0,
            .kern: 1.5
        ]

        let attributedText = NSMutableAttributedString(string: text, attributes: attributes)
        if let separatorRange = text.range(of: " | ") {
            attributedText.setAttributes(separatorAttributes, range: NSRange(separatorRange, in: text))
        }

        let textSize = attributedText.size()
        let paddingX: CGFloat = 8.0 // extra padding for radius 8
        let rectSize = NSSize(width: textSize.width + paddingX * 2, height: textSize.height + 4.0)

        // Add a margin to prevent the stroke from clipping at the edges
        let marginX: CGFloat = 1.0

        // Standard menubar height is 22
        let imageSize = NSSize(width: rectSize.width + marginX * 2, height: 22)
        let image = NSImage(size: imageSize)

        image.lockFocus()

        // Center the rect
        let rectY = (imageSize.height - rectSize.height) / 2.0
        let roundedRect = NSRect(x: marginX, y: rectY, width: rectSize.width, height: rectSize.height)
        let path = NSBezierPath(roundedRect: roundedRect, xRadius: 8, yRadius: 8)

        color.setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Draw text centered
        let textY = rectY + (rectSize.height - textSize.height) / 2.0
        let textRect = NSRect(x: marginX + paddingX, y: textY, width: textSize.width, height: textSize.height)
        attributedText.draw(in: textRect)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateButton() {
        let active = isVnKeyActive()
        guard let item = statusItem else { return }

        // Completely hide the VNKey menu tray if VNKey is not the active system input source
        item.isVisible = active
        if !active {
            return
        }

        let name: String
        if !Preferences.shared.isVietnameseMode {
            name = "E"
        } else {
            let methodName: String
            switch Preferences.shared.inputMethod {
            case .telex: methodName = "Telex"
            case .vni:   methodName = "VNI"
            }
            name = "V | \(methodName)"
        }
        item.button?.title = ""
        item.button?.image = createIconImage(text: name)
        item.button?.toolTip = "VnKey"
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "VnKey")

        // ── Language ──────────────────────────────────────────────────────
        let languageItem = makeItem(title: "Bật tiếng Việt",
                                     action: #selector(handleSetLanguage(_:)),
                                     tag: 501,
                                     isOn: Preferences.shared.isVietnameseMode)
        languageItem.keyEquivalent = " "
        languageItem.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(languageItem)
        menu.addItem(.separator())

        // ── Input Method ──────────────────────────────────────────────────
        let inputMethodMenu = NSMenu(title: "Kiểu gõ")
        let methods: [(String, InputMethodType, Int)] = [
            ("Telex", .telex, 101),
            ("VNI",   .vni,   104),
        ]
        let currentMethod = Preferences.shared.inputMethod
        for (title, method, tag) in methods {
            let item = makeItem(title: title,
                                action: #selector(handleSetInputMethod(_:)),
                                tag: tag,
                                isOn: currentMethod == method)
            inputMethodMenu.addItem(item)
        }
        let methodHeader = NSMenuItem(title: "Kiểu gõ", action: nil, keyEquivalent: "")
        methodHeader.submenu = inputMethodMenu
        menu.addItem(methodHeader)
        menu.addItem(.separator())

        // ── Tone style ────────────────────────────────────────────────────
        let toneMenu = NSMenu(title: "Bỏ dấu")
        toneMenu.addItem(makeItem(title: "Kiểu mới (oà, uý)",
                                  action: #selector(handleSetNewTone(_:)),
                                  tag: 301,
                                  isOn: Preferences.shared.isNewToneStyle))
        toneMenu.addItem(makeItem(title: "Kiểu cũ (òa, úy)",
                                  action: #selector(handleSetOldTone(_:)),
                                  tag: 302,
                                  isOn: !Preferences.shared.isNewToneStyle))
        toneMenu.addItem(.separator())
        toneMenu.addItem(makeItem(title: "Gõ w thành ư",
                                  action: #selector(handleToggleTelexWAnywhere(_:)),
                                  tag: 303,
                                  isOn: Preferences.shared.telexWAnywhere))
        toneMenu.addItem(makeItem(title: "Gõ [ thành ơ",
                                  action: #selector(handleToggleTelexBrackets(_:)),
                                  tag: 304,
                                  isOn: Preferences.shared.telexBrackets))
        toneMenu.addItem(.separator())
        toneMenu.addItem(makeItem(title: "Phục hồi từ gõ sai tiếng Việt",
                                  action: #selector(handleToggleRestoreMistyped(_:)),
                                  tag: 305,
                                  isOn: Preferences.shared.restoreMistypedVietnamese))
        let toneHeader = NSMenuItem(title: "Bỏ dấu", action: nil, keyEquivalent: "")
        toneHeader.submenu = toneMenu
        menu.addItem(toneHeader)
        menu.addItem(.separator())

        // ── Accessibility ─────────────────────────────────────────────────
        let a11yMenu = NSMenu(title: "Trợ năng")
        a11yMenu.addItem(makeItem(title: "Hiện gợi ý từ khi gõ",
                                  action: #selector(handleToggleSuggestions(_:)),
                                  tag: 401,
                                  isOn: Preferences.shared.showSuggestions))
        a11yMenu.addItem(.separator())
        a11yMenu.addItem(makeItem(title: "Hiện gợi ý từ tiếp theo",
                                  action: #selector(handleToggleNextWordPrediction(_:)),
                                  tag: 404,
                                  isOn: Preferences.shared.nextWordPredictionEnabled))
        let resetItem = NSMenuItem(title: "Xoá dữ liệu học gợi ý", action: #selector(handleResetNextWordPrediction(_:)), keyEquivalent: "")
        resetItem.target = self
        a11yMenu.addItem(resetItem)
        a11yMenu.addItem(.separator())
        a11yMenu.addItem(makeItem(title: "Ghi nhớ ngôn ngữ theo ứng dụng",
                                  action: #selector(handleTogglePerAppLanguageMemory(_:)),
                                  tag: 403,
                                  isOn: Preferences.shared.perAppLanguageMemory))
        a11yMenu.addItem(.separator())
        
        let a11yHeader = NSMenuItem(title: "Trợ năng", action: nil, keyEquivalent: "")
        a11yHeader.submenu = a11yMenu
        menu.addItem(a11yHeader)
        menu.addItem(.separator())

        // ── About / Quit ──────────────────────────────────────────────────
        let aboutItem = NSMenuItem(title: "Giới thiệu", action: #selector(handleShowAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Thoát", action: #selector(handleQuit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeItem(title: String,
                          action: Selector,
                          tag: Int,
                          isOn: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Action handlers (run in-process, no XPC)

    @objc private func handleSetLanguage(_ sender: NSMenuItem) {
        Preferences.shared.isVietnameseMode.toggle()
        rememberLanguageForCurrentApp()
        debugLog("StatusMenu: isVietnameseMode → \(Preferences.shared.isVietnameseMode)")
        refresh()
    }

    @objc private func handleTogglePerAppLanguageMemory(_ sender: NSMenuItem) {
        Preferences.shared.perAppLanguageMemory.toggle()
        debugLog("StatusMenu: perAppLanguageMemory → \(Preferences.shared.perAppLanguageMemory)")
        refresh()
    }

    private func rememberLanguageForCurrentApp() {
        guard Preferences.shared.perAppLanguageMemory else { return }
        let controller = (NSApplication.shared.delegate as? AppDelegate)?.currentController
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.theodore.inputmethod.VnKey"
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let bundleID: String? = (frontmostID != nil && frontmostID != myBundleID) ? frontmostID : controller?.lastClientBundleID
        guard let targetBundleID = bundleID else { return }
        Preferences.shared.rememberLanguageMode(Preferences.shared.isVietnameseMode, forBundleID: targetBundleID)
    }

    @objc private func handleToggleNextWordPrediction(_ sender: NSMenuItem) {
        Preferences.shared.nextWordPredictionEnabled.toggle()
        debugLog("StatusMenu: nextWordPredictionEnabled → \(Preferences.shared.nextWordPredictionEnabled)")
        refresh()
    }

    @objc private func handleResetNextWordPrediction(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Xoá dữ liệu học gợi ý?"
        alert.informativeText = "Toàn bộ từ đã học từ thói quen gõ của bạn sẽ bị xoá, chỉ còn lại các gợi ý mặc định. Không thể hoàn tác."
        alert.addButton(withTitle: "Xoá")
        alert.addButton(withTitle: "Huỷ")
        alert.alertStyle = .warning
        if let icon = Self.appIcon {
            alert.icon = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NextWordPredictor.shared.reset()
        debugLog("StatusMenu: NextWordPredictor reset")
    }

    @objc private func handleSetInputMethod(_ sender: NSMenuItem) {
        let map: [Int: InputMethodType] = [101: .telex, 104: .vni]
        guard let method = map[sender.tag] else { return }
        Preferences.shared.inputMethod = method
        debugLog("StatusMenu: inputMethod → \(method)")
        refresh()
    }

    @objc private func handleSetNewTone(_ sender: NSMenuItem) {
        Preferences.shared.isNewToneStyle = true
        debugLog("StatusMenu: toneStyle → new")
        refresh()
    }

    @objc private func handleSetOldTone(_ sender: NSMenuItem) {
        Preferences.shared.isNewToneStyle = false
        debugLog("StatusMenu: toneStyle → old")
        refresh()
    }

    @objc private func handleToggleTelexWAnywhere(_ sender: NSMenuItem) {
        Preferences.shared.telexWAnywhere.toggle()
        debugLog("StatusMenu: telexWAnywhere → \(Preferences.shared.telexWAnywhere)")
        refresh()
    }

    @objc private func handleToggleTelexBrackets(_ sender: NSMenuItem) {
        Preferences.shared.telexBrackets.toggle()
        debugLog("StatusMenu: telexBrackets → \(Preferences.shared.telexBrackets)")
        refresh()
    }

    @objc private func handleToggleSuggestions(_ sender: NSMenuItem) {
        Preferences.shared.showSuggestions.toggle()
        debugLog("StatusMenu: showSuggestions → \(Preferences.shared.showSuggestions)")
        refresh()
    }

    @objc private func handleToggleRestoreMistyped(_ sender: NSMenuItem) {
        Preferences.shared.restoreMistypedVietnamese.toggle()
        debugLog("StatusMenu: restoreMistypedVietnamese → \(Preferences.shared.restoreMistypedVietnamese)")
        refresh()
    }

    @objc private func handleShowAbout(_ sender: NSMenuItem) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        NSApp.activate(ignoringOtherApps: true)
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "VnKey",
            .applicationVersion: version,
            .version: build,
            .credits: NSAttributedString(string: "Bộ gõ tiếng Việt cho macOS.\nHỗ trợ Telex, VNI, gõ tắt và gợi ý từ.\n⌘⇧Space để bật/tắt tiếng Việt.")
        ]
        if let icon = Self.appIcon {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func handleQuit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Debug

    private func debugLog(_ msg: String) {
        #if DEBUG
        let line = "\(Date()) \(msg)\n"
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
}
