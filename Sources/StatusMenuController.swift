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

    // MARK: - Public API

    /// Call once from AppDelegate.applicationDidFinishLaunching to install the status item.
    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = buildMenu()
        statusItem = item
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        
        updateButton()
    }

    /// Rebuild the menu so check-marks reflect current Preferences.
    /// Called automatically whenever a preference changes.
    func refresh() {
        statusItem?.menu = buildMenu()
        updateButton()
    }

    @objc private func inputSourceChanged() {
        updateButton()
    }

    private func isVnKeyActive() -> Bool {
        let currentSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let idPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let myBundleID = Bundle.main.bundleIdentifier ?? "com.ahtstudio.inputmethod.VnKey"
            // The actual input source ID defined in Info.plist has a ".mac" suffix
            return id == myBundleID || id == "\(myBundleID).mac"
        }
        return false
    }

    private func createIconImage(text: String, isActive: Bool) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let alpha: CGFloat = isActive ? 1.0 : 0.4
        let color = NSColor.black.withAlphaComponent(alpha)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        let textSize = text.size(withAttributes: attributes)
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
        text.draw(in: textRect, withAttributes: attributes)
        
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateButton() {
        let name: String
        switch Preferences.shared.inputMethod {
        case .telex:        name = "Telex"
        case .simpleTelex:  name = "SimpleTelex"
        case .simpleTelex2: name = "SimpleTelex2"
        case .vni:          name = "VNI"
        }
        statusItem?.button?.title = ""
        statusItem?.button?.image = createIconImage(text: name, isActive: isVnKeyActive())
        statusItem?.button?.toolTip = "VnKey — Bảng mã: \(Preferences.shared.charset.rawValue)"
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "VnKey")

        // ── Input Method ──────────────────────────────────────────────────
        let inputMethodMenu = NSMenu(title: "Kiểu gõ")
        let methods: [(String, InputMethodType, Int)] = [
            ("Telex",        .telex,        101),
            ("Simple Telex", .simpleTelex,  102),
            ("Simple Telex 2", .simpleTelex2, 103),
            ("VNI",          .vni,          104),
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

        // ── Charset ───────────────────────────────────────────────────────
        let charsetMenu = NSMenu(title: "Bảng mã")
        let charsets: [(String, CharsetType, Int)] = [
            ("Unicode",          .unicode,         201),
            ("Unicode Tổ hợp",   .unicodeComposed, 202),
            ("VNI Windows",      .vniWindows,      203),
            ("TCVN3 (ABC)",      .tcvn3,           204),
            ("VIQR",             .viqr,            205),
            ("VPS",              .vps,             206),
            ("VNI Mac",          .vniMac,          207),
            ("Bách Khoa HCM 1",  .bkhcm1,          208),
            ("Bách Khoa HCM 2",  .bkhcm2,          209),
            ("CP 1258",          .cp1258,          210),
        ]
        let currentCharset = Preferences.shared.charset
        for (title, charset, tag) in charsets {
            let item = makeItem(title: title,
                                action: #selector(handleSetCharset(_:)),
                                tag: tag,
                                isOn: currentCharset == charset)
            charsetMenu.addItem(item)
        }
        let charsetHeader = NSMenuItem(title: "Bảng mã", action: nil, keyEquivalent: "")
        charsetHeader.submenu = charsetMenu
        menu.addItem(charsetHeader)
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
        let toneHeader = NSMenuItem(title: "Bỏ dấu", action: nil, keyEquivalent: "")
        toneHeader.submenu = toneMenu
        menu.addItem(toneHeader)
        menu.addItem(.separator())

        // ── Accessibility ─────────────────────────────────────────────────
        let a11yMenu = NSMenu(title: "Trợ năng")
        a11yMenu.addItem(makeItem(title: "Hiện gợi ý từ",
                                  action: #selector(handleToggleSuggestions(_:)),
                                  tag: 401,
                                  isOn: Preferences.shared.showSuggestions))
        a11yMenu.addItem(.separator())
        a11yMenu.addItem(makeItem(title: "Kiểm tra tiếng Anh",
                                  action: #selector(handleToggleEnglishFSM(_:)),
                                  tag: 402,
                                  isOn: Preferences.shared.enableEnglishFSM))
        a11yMenu.addItem(makeItem(title: "Kiểm tra từ khoá lập trình",
                                  action: #selector(handleToggleProgrammingFSM(_:)),
                                  tag: 403,
                                  isOn: Preferences.shared.enableProgrammingFSM))
        let a11yHeader = NSMenuItem(title: "Trợ năng", action: nil, keyEquivalent: "")
        a11yHeader.submenu = a11yMenu
        menu.addItem(a11yHeader)

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

    @objc private func handleSetInputMethod(_ sender: NSMenuItem) {
        let map: [Int: InputMethodType] = [101: .telex, 102: .simpleTelex,
                                           103: .simpleTelex2, 104: .vni]
        guard let method = map[sender.tag] else { return }
        Preferences.shared.inputMethod = method
        debugLog("StatusMenu: inputMethod → \(method)")
        refresh()
    }

    @objc private func handleSetCharset(_ sender: NSMenuItem) {
        let map: [Int: CharsetType] = [
            201: .unicode, 202: .unicodeComposed, 203: .vniWindows,
            204: .tcvn3,   205: .viqr,            206: .vps,
            207: .vniMac,  208: .bkhcm1,          209: .bkhcm2,
            210: .cp1258,
        ]
        guard let charset = map[sender.tag] else { return }
        Preferences.shared.charset = charset
        debugLog("StatusMenu: charset → \(charset.rawValue)")
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

    @objc private func handleToggleSuggestions(_ sender: NSMenuItem) {
        Preferences.shared.showSuggestions.toggle()
        debugLog("StatusMenu: showSuggestions → \(Preferences.shared.showSuggestions)")
        refresh()
    }

    @objc private func handleToggleEnglishFSM(_ sender: NSMenuItem) {
        Preferences.shared.enableEnglishFSM.toggle()
        debugLog("StatusMenu: enableEnglishFSM → \(Preferences.shared.enableEnglishFSM)")
        refresh()
    }

    @objc private func handleToggleProgrammingFSM(_ sender: NSMenuItem) {
        Preferences.shared.enableProgrammingFSM.toggle()
        debugLog("StatusMenu: enableProgrammingFSM → \(Preferences.shared.enableProgrammingFSM)")
        refresh()
    }

    // MARK: - Debug

    private func debugLog(_ msg: String) {
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
    }
}
