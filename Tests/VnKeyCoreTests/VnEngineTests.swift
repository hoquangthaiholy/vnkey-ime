import XCTest
@testable import VnKeyCore

/// Pins down current VnEngine behavior so the FSM can be optimized (e.g. incremental
/// parsing instead of re-parsing the whole buffer per keystroke) without silently
/// regressing any of the cases that were manually verified during development.
/// Every expected value here was captured by actually running VnEngine, not guessed.
final class VnEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Every test sets the preferences it cares about explicitly, but reset the
        // full set here so no test can leak state into another via UserDefaults.
        Preferences.shared.isNewToneStyle = false
        Preferences.shared.restoreMistypedVietnamese = true
        Preferences.shared.telexWAnywhere = false
        Preferences.shared.telexBrackets = false
    }

    private func telex(_ raw: String, newTone: Bool = false) -> String {
        VnEngine.process(raw: raw, method: .telex, isNewToneStyle: newTone)
    }

    private func vni(_ raw: String, newTone: Bool = false) -> String {
        VnEngine.process(raw: raw, method: .vni, isNewToneStyle: newTone)
    }

    // MARK: - Basic tone application (Telex)

    func testBasicToneKeys() {
        XCTAssertEqual(telex("as"), "á")
        XCTAssertEqual(telex("af"), "à")
        XCTAssertEqual(telex("ar"), "ả")
        XCTAssertEqual(telex("ax"), "ã")
        XCTAssertEqual(telex("aj"), "ạ")
    }

    func testToneWithOnsetAndCoda() {
        XCTAssertEqual(telex("bans"), "bán")
        XCTAssertEqual(telex("chungs"), "chúng")
        XCTAssertEqual(telex("hoas"), "hóa") // old tone style (see testToneStyleOnOaCluster for the style diff)
        XCTAssertEqual(telex("nangj"), "nạng")
    }

    // MARK: - Circumflex double-vowel modifiers (Telex)

    func testDoubleVowelCircumflex() {
        XCTAssertEqual(telex("caa"), "câ")
        XCTAssertEqual(telex("mootj"), "một")
        XCTAssertEqual(telex("bee"), "bê")
    }

    func testDoubleVowelTripleCancelCollapsesToLiteral() {
        // Typing the modifier a third time cancels the circumflex; the cancelled
        // key becomes a literal character in place, same as the tone/diacritic
        // cancel cases above (not the raw, uncollapsed "caaa").
        XCTAssertEqual(telex("caaa"), "caa")
    }

    // MARK: - Đ (dd)

    func testDStroke() {
        XCTAssertEqual(telex("ddi"), "đi")
    }

    func testDoubleDInCodaPositionIsInvalidRestoredAsRaw() {
        // Once past the onset, "dd" is not a valid coda, so the whole word is
        // restored unchanged rather than partially transformed.
        XCTAssertEqual(telex("khoedd"), "khoedd")
    }

    // MARK: - qu / gi glide handling

    func testQuGlide() {
        XCTAssertEqual(telex("quas"), "quá")
    }

    func testGiGlideWithFollowingVowel() {
        XCTAssertEqual(telex("giups"), "giúp")
    }

    func testGiGlideWithoutFollowingVowel() {
        XCTAssertEqual(telex("gif"), "gì")
    }

    // MARK: - "z" cancels composition (Telex only)

    func testZCancelsComposition() {
        XCTAssertEqual(telex("toiz"), "toi")
    }

    // MARK: - Tone-cancel escape sequences (order-preserving fix)

    func testToneCancelAdjacent() {
        // Trigger then immediate cancel, before any coda: "tesst" -> "test"
        XCTAssertEqual(telex("tesst"), "test")
    }

    func testToneCancelAfterCoda() {
        // Trigger, then coda typed, then cancel: "tests" -> "test" (not "tets")
        XCTAssertEqual(telex("tests"), "test")
    }

    func testToneCancelPostfixStyle() {
        // Tone applied at the very end (postfix), then cancelled immediately.
        XCTAssertEqual(telex("chungss"), "chungs")
    }

    func testToneCancelVNI() {
        XCTAssertEqual(vni("van1"), "ván")
        XCTAssertEqual(vni("van11"), "van1")
    }

    // MARK: - VNI breve/whisker flag isolation

    func testVNIBreveDoesNotCorruptWhisker() {
        XCTAssertEqual(vni("a8"), "ă")
        // A subsequent unrelated whisker key ("7") must not misread the earlier
        // breve as an already-applied whisker and revert it to plain "a".
        // The word ends up structurally invalid either way and is restored as raw.
        XCTAssertEqual(vni("a87"), "a87")
    }

    // MARK: - English-word restoration (restoreMistypedVietnamese)

    func testEnglishWordsRestoredWhenInvalid() {
        XCTAssertEqual(telex("compressor"), "compressor")
        XCTAssertEqual(telex("transformer"), "transformer")
        XCTAssertEqual(telex("keyboard"), "keyboard")
        XCTAssertEqual(telex("function"), "function")
    }

    func testValidSyllableIsNotTreatedAsEnglish() {
        // "tét" is a structurally valid Vietnamese syllable even though it
        // came from typing the English word "test".
        XCTAssertEqual(telex("test"), "tét")
    }

    func testRestoreMistypedVietnameseCanBeDisabled() {
        Preferences.shared.restoreMistypedVietnamese = false
        XCTAssertNotEqual(telex("compressor"), "compressor")
    }

    // MARK: - Telex opt-in shortcuts: w-anywhere, brackets

    func testWDoesNothingByDefault() {
        XCTAssertEqual(telex("w"), "w")
        XCTAssertEqual(telex("wa"), "wa")
    }

    func testWStillConvertsExistingVowelByDefault() {
        // The core whisker mechanism (w modifies an existing vowel) is always on;
        // only the "bare w with no vowel yet" shortcut is gated by the toggle.
        XCTAssertEqual(telex("tuwf"), "từ")
        XCTAssertEqual(telex("uongw"), "ương")
    }

    func testWAnywhereToggleEnablesBareW() {
        Preferences.shared.telexWAnywhere = true
        XCTAssertEqual(telex("w"), "ư")
        XCTAssertEqual(telex("wa"), "ưa")
    }

    func testBracketsDoNothingByDefault() {
        XCTAssertEqual(telex("tho["), "tho[")
    }

    func testBracketsToggleEnablesShortcut() {
        Preferences.shared.telexBrackets = true
        XCTAssertEqual(telex("tho["), "thơ")
        XCTAssertEqual(telex("chu]"), "chư")
    }

    // MARK: - Tone placement rules (old vs new style)

    func testToneStyleOnOaCluster() {
        // "oa" with no coda differs between old/new style placement.
        XCTAssertEqual(telex("hoaf", newTone: false), "hòa")
        XCTAssertEqual(telex("hoaf", newTone: true), "hoà")
    }

    func testToneStyleOnUyCluster() {
        XCTAssertEqual(telex("tuys", newTone: false), "túy")
        XCTAssertEqual(telex("tuys", newTone: true), "tuý")
    }

    // MARK: - Capitalization preservation

    func testCapitalizationFirstUpper() {
        XCTAssertEqual(telex("Bans"), "Bán")
    }

    func testCapitalizationAllUpper() {
        XCTAssertEqual(telex("BANS"), "BÁN")
    }

    // MARK: - VNI basics

    func testVNIToneKeys() {
        XCTAssertEqual(vni("ban1"), "bán")
        XCTAssertEqual(vni("nang5"), "nạng")
    }

    func testVNIToneOnInvalidCodaFallsBackToRaw() {
        // "s" is not a valid Vietnamese coda, so the tone-key digit can't save it.
        XCTAssertEqual(vni("as1"), "as1")
    }

    func testVNIHatAndStroke() {
        XCTAssertEqual(vni("a6"), "â")
        XCTAssertEqual(vni("d9i"), "đi")
    }

    // MARK: - Empty input

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(telex(""), "")
    }
}
