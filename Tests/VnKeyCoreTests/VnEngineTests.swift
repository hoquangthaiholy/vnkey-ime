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

    func testDStrokeWithNoFollowingVowelIsStillTrusted() {
        // "đ" has no English equivalent, so creating it is always deliberate —
        // e.g. abbreviations like "ĐN" — and must not be discarded just because
        // no vowel follows (regression: this used to fall back to raw "DDN").
        XCTAssertEqual(telex("ddn"), "đn")
        XCTAssertEqual(telex("DDN"), "ĐN")
        XCTAssertEqual(vni("d9n"), "đn")
    }

    func testDoubleDInCodaPositionIsInvalidRestoredAsRaw() {
        // Once past the onset, "dd" is not a valid coda, and no đ was ever
        // created, so the whole word is restored unchanged.
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

    // MARK: - Scrambled / out-of-order diacritic typing (Telex)

    // Tone is stored as an enum and only rendered onto the vowel cluster at the
    // very end of processing, so — unlike the hat/whisker modifiers, which mutate
    // the vowel string immediately — *when* the tone key is pressed relative to
    // the rest of the syllable doesn't matter, only that it's pressed after at
    // least one vowel exists. These pin down that this holds for real multi-step
    // vowel clusters, not just single-vowel syllables.
    func testToneOrderIndependentAroundWhiskerProgression() {
        XCTAssertEqual(telex("nguwowfi"), "người") // standard order: whisker, whisker, tone
        XCTAssertEqual(telex("nguwfowi"), "người") // tone fired before the 2nd whisker completes ươ
    }

    func testToneOrderIndependentAroundCircumflex() {
        XCTAssertEqual(telex("vieetj"), "việt") // standard order: circumflex, tone
        XCTAssertEqual(telex("vietje"), "việt") // tone fired before circumflex is formed
        XCTAssertEqual(telex("chuyeern"), "chuyển")
        XCTAssertEqual(telex("chuyerne"), "chuyển") // tone before circumflex, coda typed last
    }

    func testToneOrderIndependentBeforeOrAfterCoda() {
        XCTAssertEqual(telex("tuwowngr"), "tưởng") // standard: both whiskers, then tone, no coda yet
        XCTAssertEqual(telex("tuwrowng"), "tưởng") // tone fired between the two whisker presses
    }

    // A diacritic/whisker key pressed before any vowel exists yet can't attach to
    // anything (there's nothing to modify), so it's correctly left as a literal
    // character in both methods — this isn't an inconsistency, just the one order
    // requirement ("vowel must exist first") both FSMs share.
    func testDiacriticKeyBeforeAnyVowelIsLiteralInBothMethods() {
        XCTAssertEqual(telex("hfoan"), "hfoan")
        XCTAssertEqual(vni("t7uong"), "t7uong")
    }

    // MARK: - VNI progressive whisker (regression: 2nd "7" used to always revert)

    func testVNIWhiskerProgressesLikeTelexRatherThanAlwaysReverting() {
        // Standard VNI convention for the ươ cluster is one "7" per vowel:
        // u -> ư, then o -> ơ (which combines with the preceding ư into ươ).
        // This used to be broken: since whiskerApplied was already true from the
        // first "7", the second "7" unconditionally reverted u back from ư
        // instead of trying to progress ưo -> ươ first (mirroring how Telex's
        // repeated "w" handles the exact same ưo -> ươ case).
        XCTAssertEqual(vni("tu7o7ng"), "tương")
        XCTAssertEqual(vni("d9u7o7ng2"), "đường")
        // A genuine revert (pressing "7" twice on a vowel that has nowhere
        // further to go) must still work — the cancelled key is preserved
        // literally, same convention as every other cancel case in this file.
        XCTAssertEqual(vni("u77"), "u7")
    }

    // MARK: - Explicit-cancel raw-fallback loophole (regression: "class" -> "clas")

    func testCancelledToneDoesNotSuppressRawFallbackForInvalidOnset() {
        // "class": the vowel 'a' plus the first 's' forms a tone (sắc), and the
        // second 's' cancels it — hasExplicitCancel becomes true. But that only
        // proves the *cancel reconstruction* (literalSuffix) is trustworthy; it
        // says nothing about the onset "cl", which was never valid Vietnamese.
        // Regression: hasExplicitCancel alone used to skip the raw-fallback
        // check entirely, so this silently produced "clas" (a dropped letter)
        // instead of falling back to the untouched raw text.
        XCTAssertEqual(telex("class"), "class")
        XCTAssertEqual(telex("bless"), "bless")
        XCTAssertEqual(telex("glass"), "glass")
    }

    func testGenuineToneCancelStillWorksAfterFallbackFix() {
        // Make sure tightening the fallback check didn't regress the legitimate
        // cancel cases it was modeled on, where onset/vowels/coda ARE valid
        // Vietnamese once the literal suffix is set aside.
        XCTAssertEqual(telex("tesst"), "test")
        XCTAssertEqual(telex("tests"), "test")
        XCTAssertEqual(telex("chungss"), "chungs")
    }

    // MARK: - Known limitation: English words that collide with Telex tone keys

    // Telex overloads s/f/r/x/j as both tone triggers and literal letters. When
    // an English word happens to look like onset+vowel(+coda) with one of those
    // letters in the tone-key position, the result is structurally
    // indistinguishable from real Vietnamese and restoreMistypedVietnamese's
    // *structural* validity check can't tell them apart (it would need a full
    // English/Vietnamese word dictionary to do better). This is not unique to
    // this engine — Unikey and other Telex IMEs have the identical limitation.
    // These tests pin down the CURRENT behavior so future changes don't shift it
    // by accident; they are not asserting this is correct or desired output.
    func testKnownLimitationSingleToneKeyLetterInEnglishWord() {
        XCTAssertEqual(telex("test"), "tét")
        XCTAssertEqual(telex("rest"), "rét")
        XCTAssertEqual(telex("best"), "bét")
        XCTAssertEqual(telex("must"), "mút")
        XCTAssertEqual(telex("list"), "lít")
        XCTAssertEqual(telex("sort"), "sỏt")
        XCTAssertEqual(telex("port"), "pỏt")
        XCTAssertEqual(telex("part"), "pảt")
        XCTAssertEqual(telex("cart"), "cảt")
    }

    // A second, distinct flavor of the same limitation: an English word with a
    // *doubled* tone-key letter (geminate consonant, e.g. "ss" in "pass") is
    // structurally identical to "trigger tone, then cancel it" — the FSM has no
    // way to know the second letter was meant literally, not as a cancel signal.
    // Whether this drops a letter or falls back to raw depends on whether the
    // onset ends up valid Vietnamese: "class"/"bless"/"glass" have invalid
    // onsets (cl/bl/gl) so they fall back to raw correctly (see
    // testCancelledToneDoesNotSuppressRawFallbackForInvalidOnset above), but a
    // single-consonant onset like "pass" or "less" looks fully valid and the
    // doubled letter is silently lost.
    func testKnownLimitationDoubledToneKeyLetterWithValidOnsetDropsALetter() {
        XCTAssertEqual(telex("pass"), "pas") // expected "pass": loses one 's'
        XCTAssertEqual(telex("less"), "les") // expected "less": loses one 's'
    }
}
