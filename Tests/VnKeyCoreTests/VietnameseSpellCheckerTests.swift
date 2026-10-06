import XCTest
@testable import VnKeyCore

final class VietnameseSpellCheckerTests: XCTestCase {

    // MARK: - Phonetic Harmony (Luật hòa thanh Hỏi / Ngã trong từ láy)

    func testPhoneticHarmonyHoiNgaCorrection() {
        // Lỗi thanh Ngã đi với Ngang -> sửa thành Hỏi
        let c1 = VietnameseSpellChecker.correctPhrase("nghĩ", "ngơi")
        XCTAssertNotNil(c1)
        XCTAssertEqual(c1?.w1, "nghỉ")
        XCTAssertEqual(c1?.w2, "ngơi")

        // Lỗi thanh Hỏi đi với Nặng -> sửa thành Ngã
        let c2 = VietnameseSpellChecker.correctPhrase("đẹp", "đẻ")
        XCTAssertNotNil(c2)
        XCTAssertEqual(c2?.w1, "đẹp")
        XCTAssertEqual(c2?.w2, "đẽ")

        // Lỗi thanh Hỏi đi với Huyền -> sửa thành Ngã
        let c3 = VietnameseSpellChecker.correctPhrase("rỏ", "ràng")
        XCTAssertNotNil(c3)
        XCTAssertEqual(c3?.w1, "rõ")
        XCTAssertEqual(c3?.w2, "ràng")

        // Lỗi thanh Ngã đi với Sắc -> sửa thành Hỏi
        let c4 = VietnameseSpellChecker.correctPhrase("mát", "mẽ")
        XCTAssertNotNil(c4)
        XCTAssertEqual(c4?.w1, "mát")
        XCTAssertEqual(c4?.w2, "mẻ")

        // Lỗi thanh Hỏi đi với Huyền -> sửa thành Ngã
        let c5 = VietnameseSpellChecker.correctPhrase("dể", "dàng")
        XCTAssertNotNil(c5)
        XCTAssertEqual(c5?.w1, "dễ")
        XCTAssertEqual(c5?.w2, "dàng")
    }

    func testPhoneticHarmonyAlreadyCorrectWordsPassThrough() {
        // Đã đúng chính tả: không gợi ý sửa đổi
        XCTAssertNil(VietnameseSpellChecker.correctPhrase("nghỉ", "ngơi"))
        XCTAssertNil(VietnameseSpellChecker.correctPhrase("đẹp", "đẽ"))
        XCTAssertNil(VietnameseSpellChecker.correctPhrase("rõ", "ràng"))
        XCTAssertNil(VietnameseSpellChecker.correctPhrase("vui", "vẻ"))
        XCTAssertNil(VietnameseSpellChecker.correctPhrase("mát", "mẻ"))
    }

    // MARK: - Common Mistakes (Các cặp từ sai chính tả phổ biến)

    func testCommonMistakesCorrection() {
        let testCases: [(w1: String, w2: String, expected1: String, expected2: String)] = [
            ("trân", "thành", "chân", "thành"),
            ("sắp", "xắp", "sắp", "xếp"),
            ("sáng", "lạng", "xán", "lạn"),
            ("giành", "dụm", "dành", "dụm"),
            ("dành", "giật", "giành", "giật"),
            ("bổ", "xung", "bổ", "sung"),
            ("suất", "sắc", "xuất", "sắc"),
            ("chính", "xách", "chính", "sách"),
            ("thăm", "quan", "tham", "quan"),
            ("đọc", "giả", "độc", "giả"),
            ("bàng", "quang", "bàng", "quan")
        ]

        for tc in testCases {
            let res = VietnameseSpellChecker.correctPhrase(tc.w1, tc.w2)
            XCTAssertNotNil(res, "Failed to correct \(tc.w1) \(tc.w2)")
            XCTAssertEqual(res?.w1, tc.expected1)
            XCTAssertEqual(res?.w2, tc.expected2)
        }
    }

    func testCapitalizationPreservedInCorrection() {
        let res = VietnameseSpellChecker.correctPhrase("Trân", "thành")
        XCTAssertNotNil(res)
        XCTAssertEqual(res?.w1, "Chân")
        XCTAssertEqual(res?.w2, "thành")

        let allUpper = VietnameseSpellChecker.correctPhrase("TRÂN", "THÀNH")
        XCTAssertNotNil(allUpper)
        XCTAssertEqual(allUpper?.w1, "CHÂN")
        XCTAssertEqual(allUpper?.w2, "THÀNH")
    }

    // MARK: - Sentence Level Checking

    func testSentenceChecking() {
        let sentence1 = "Tôi trân thành cảm ơn các bạn."
        let corr1 = VietnameseSpellChecker.checkSentence(sentence1)
        XCTAssertEqual(corr1.count, 1)
        XCTAssertEqual(corr1.first?.original, "trân thành")
        XCTAssertEqual(corr1.first?.replacement, "chân thành")

        let sentence2 = "Sau giờ làm việc, chúng tôi cần được nghĩ ngơi."
        let corr2 = VietnameseSpellChecker.checkSentence(sentence2)
        XCTAssertEqual(corr2.count, 1)
        XCTAssertEqual(corr2.first?.original, "nghĩ ngơi")
        XCTAssertEqual(corr2.first?.replacement, "nghỉ ngơi")

        let correctSentence = "Tôi chân thành cảm ơn bạn đã giúp đỡ, chúc bạn vui vẻ."
        let corr3 = VietnameseSpellChecker.checkSentence(correctSentence)
        XCTAssertEqual(corr3.count, 0)
    }
}
