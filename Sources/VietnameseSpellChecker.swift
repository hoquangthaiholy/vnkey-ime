import Foundation

public enum ToneSystem {
    case bong // Ngang (none), Sắc, Hỏi
    case tram // Huyền, Nặng, Ngã
}

public struct SpellCorrection {
    public let original: String
    public let replacement: String
    public let range: NSRange
    public let explanation: String

    public init(original: String, replacement: String, range: NSRange, explanation: String) {
        self.original = original
        self.replacement = replacement
        self.range = range
        self.explanation = explanation
    }
}

public class VietnameseSpellChecker {
    public static let shared = VietnameseSpellChecker()

    // Tra cứu cụm từ sai phổ biến (ch/tr, s/x, d/gi/r, hỏi/ngã)
    private static let commonMistakes: [String: (replacement: String, reason: String)] = [
        "trân thành": ("chân thành", "Chân thành: thật thà, xuất phát từ đáy lòng (chân), không phải 'trân'"),
        "sắp xắp": ("sắp xếp", "Sắp xếp: bài trí, thu xếp ngăn nắp"),
        "sáng lạng": ("xán lạn", "Xán lạn: tươi sáng, rực rỡ (từ Hán-Việt)"),
        "giành dụm": ("dành dụm", "Dành dụm: để dành, tiết kiệm gom góp dần"),
        "dành giật": ("giành giật", "Giành giật: tranh đoạt lấy về mình"),
        "bổ xung": ("bổ sung", "Bổ sung: thêm vào cho đầy đủ"),
        "suất sắc": ("xuất sắc", "Xuất sắc: vượt trội hẳn lên so với thông thường"),
        "chính xách": ("chính sách", "Chính sách: chủ trương, biện pháp hành động"),
        "cọ sát": ("cọ xát", "Cọ xát: cọ qua cọ lại, ma sát trải nghiệm"),
        "bàng quang": ("bàng quan", "Bàng quan: đứng ngoài xem, thờ ơ; không nhầm với bộ phận bàng quang"),
        "thăm quan": ("tham quan", "Tham quan: quan sát, xem xét để mở mang hiểu biết"),
        "đọc giả": ("độc giả", "Độc giả: người đọc sách báo (từ Hán-Việt 'độc')"),
        "sát nhập": ("sáp nhập", "Sáp nhập: gộp lại làm một"),
        "chuẩn đoán": ("chẩn đoán", "Chẩn đoán: xác định bệnh trạng (chẩn: xem xét)"),
        "chắp bút": ("chấp bút", "Chấp bút: cầm bút viết theo ý người khác (chấp: cầm, nắm)"),
        "chau chuốt": ("trau chuốt", "Trau chuốt: mài giũa, sửa sang tỉ mỉ"),
        "vô hình chung": ("vô hình trung", "Vô hình trung: trong cái vô hình, ngẫu nhiên tự tạo thành"),
        "khoát lác": ("khoác lác", "Khoác lác: nói quá sự thật, bốc phét"),
        "tựu chung": ("tựu trung", "Tựu trung: tóm lại, rốt cuộc quy về một mối"),
        "phố sá": ("phố xá", "Phố xá: nơi phố xá đông đúc"),
        "suôn xẻ": ("suôn sẻ", "Suôn sẻ: trôi chảy, thuận lợi"),
        "sơ xuất": ("sơ suất", "Sơ suất: thiếu cẩn thận, để sót lỗi"),
        "sơ xác": ("xơ xác", "Xơ xác: rách nát, tơi tả, hoang tàn"),
        "nói trung": ("nói chung", "Nói chung: khái quát lại"),
        "bạc mạng": ("bạt mạng", "Bạt mạng: liều lĩnh coi thường tính mạng"),
        "lòng cốt": ("nòng cốt", "Nòng cốt: bộ phận cốt lõi, chủ lực"),
        "giả thuyết": ("giả thuyết", "Giả thuyết: điều đặt ra để chứng minh")
    ]

    // Chuyển đổi hỏi <-> ngã cho âm tiết
    private static let hoiToNgaMap: [String: String] = [
        "nghỉ": "nghĩ", "nghĩ": "nghỉ",
        "đẻ": "đẽ", "đẽ": "đẻ",
        "rỏ": "rõ", "rõ": "rỏ",
        "mẻ": "mẽ", "mẽ": "mẻ",
        "dể": "dễ", "dễ": "dể",
        "vẻ": "vẽ", "vẽ": "vẻ",
        "vả": "vã", "vã": "vả",
        "sẻ": "sẽ", "sẽ": "sẻ",
        "nhỏ": "nhõ", "nhõ": "nhỏ",
        "mở": "mỡ", "mỡ": "mở",
        "lẻ": "lẽ", "lẽ": "lẻ",
        "kỹ": "kỷ", "kỷ": "kỹ",
        "củ": "cũ", "cũ": "củ"
    ]

    /// Trả về hệ thanh điệu (Bổng: Ngang, Sắc, Hỏi / Trầm: Huyền, Nặng, Ngã) của từ
    public static func getToneSystem(for word: String) -> ToneSystem? {
        let lower = word.lowercased()
        var foundTone: Tone?
        for char in lower {
            if let info = VnEngine.charToToneInfo[char], info.tone != .none {
                foundTone = info.tone
                break
            }
        }
        let tone = foundTone ?? .none
        switch tone {
        case .none, .sac, .hoi:
            return .bong
        case .huyen, .nang, .nga:
            return .tram
        }
    }

    /// Trả về dấu thanh cụ thể của từ
    public static func getTone(for word: String) -> Tone {
        let lower = word.lowercased()
        for char in lower {
            if let info = VnEngine.charToToneInfo[char], info.tone != .none {
                return info.tone
            }
        }
        return .none
    }

    /// Kiểm tra và sửa lỗi chính tả cho cụm 2 từ (Bigram)
    public static func correctPhrase(_ w1: String, _ w2: String) -> (w1: String, w2: String, reason: String)? {
        let rawPhrase = "\(w1.lowercased()) \(w2.lowercased())"
        
        // 1. Kiểm tra từ điển các lỗi sai phổ biến
        if let mistake = commonMistakes[rawPhrase] {
            let parts = mistake.replacement.components(separatedBy: " ")
            if parts.count == 2 {
                let fixed1 = restoreCasing(original: w1, corrected: parts[0])
                let fixed2 = restoreCasing(original: w2, corrected: parts[1])
                return (fixed1, fixed2, mistake.reason)
            }
        }

        // 2. Kiểm tra quy luật hòa thanh thanh điệu trong từ láy
        if let corrected = checkPhoneticHarmony(w1: w1, w2: w2) {
            return corrected
        }

        return nil
    }

    /// Kiểm tra quy luật hòa thanh Hỏi / Ngã trong từ láy đôi
    public static func checkPhoneticHarmony(w1: String, w2: String) -> (w1: String, w2: String, reason: String)? {
        let low1 = w1.lowercased()
        let low2 = w2.lowercased()

        // Phải có đặc điểm từ láy (cùng phụ âm đầu hoặc vần)
        guard isLikelyReduplicative(low1, low2) else { return nil }

        let sys1 = getToneSystem(for: low1)
        let sys2 = getToneSystem(for: low2)
        guard let s1 = sys1, let s2 = sys2, s1 != s2 else { return nil }

        let tone1 = getTone(for: low1)
        let tone2 = getTone(for: low2)

        // Quy luật Bổng: Ngang, Sắc, Hỏi
        // Quy luật Trầm: Huyền, Nặng, Ngã
        // Nếu một từ mang thanh chuẩn (Ngang/Sắc hoặc Huyền/Nặng), từ còn lại mang Hỏi/Ngã
        // thì từ Hỏi/Ngã phải điều chỉnh theo thanh của từ chuẩn:
        
        // Trường hợp 1: w1 mang dấu hỏi/ngã, w2 mang thanh chuẩn
        if (tone1 == .hoi || tone1 == .nga) && (tone2 == .none || tone2 == .sac || tone2 == .huyen || tone2 == .nang) {
            let targetSystem = s2
            let expectedTone: Tone = (targetSystem == .bong) ? .hoi : .nga
            if tone1 != expectedTone {
                if let flipped = hoiToNgaMap[low1] {
                    let fixed1 = restoreCasing(original: w1, corrected: flipped)
                    let reason = (expectedTone == .hoi) ?
                        "Quy luật hòa thanh bổng: đi với '\(w2)' (\(targetSystem == .bong ? "Bổng" : "Trầm")), '\(w1)' cần dùng dấu Hỏi" :
                        "Quy luật hòa thanh trầm: đi với '\(w2)' (\(targetSystem == .bong ? "Bổng" : "Trầm")), '\(w1)' cần dùng dấu Ngã"
                    return (fixed1, w2, reason)
                }
            }
        }

        // Trường hợp 2: w2 mang dấu hỏi/ngã, w1 mang thanh chuẩn
        if (tone2 == .hoi || tone2 == .nga) && (tone1 == .none || tone1 == .sac || tone1 == .huyen || tone1 == .nang) {
            let targetSystem = s1
            let expectedTone: Tone = (targetSystem == .bong) ? .hoi : .nga
            if tone2 != expectedTone {
                if let flipped = hoiToNgaMap[low2] {
                    let fixed2 = restoreCasing(original: w2, corrected: flipped)
                    let reason = (expectedTone == .hoi) ?
                        "Quy luật hòa thanh bổng: đi với '\(w1)' (\(targetSystem == .bong ? "Bổng" : "Trầm")), '\(w2)' cần dùng dấu Hỏi" :
                        "Quy luật hòa thanh trầm: đi với '\(w1)' (\(targetSystem == .bong ? "Bổng" : "Trầm")), '\(w2)' cần dùng dấu Ngã"
                    return (w1, fixed2, reason)
                }
            }
        }

        return nil
    }

    /// Kiểm tra hai từ có khả năng là từ láy đôi
    private static func isLikelyReduplicative(_ w1: String, _ w2: String) -> Bool {
        if w1.isEmpty || w2.isEmpty { return false }
        // Cùng phụ âm đầu (ví dụ: đ - đ, r - r, v - v, m - m, n - n, ng - ng...)
        if let f1 = w1.first, let f2 = w2.first, f1 == f2 {
            return true
        }
        // Trường hợp cụ thể đã ghi nhận trong từ điển hòa thanh
        if (w1 == "nghỉ" || w1 == "nghĩ") && w2 == "ngơi" { return true }
        if (w2 == "nghỉ" || w2 == "nghĩ") && w1 == "ngơi" { return true }
        return false
    }

    /// Quét câu văn bản và trả về danh sách các vị trí cần sửa lỗi chính tả
    public static func checkSentence(_ text: String) -> [SpellCorrection] {
        if text.isEmpty { return [] }
        var corrections: [SpellCorrection] = []

        // Tách câu thành các từ kèm NSRange
        let nsString = text as NSString
        var tokens: [(word: String, range: NSRange)] = []
        
        let pattern = #"\b[\p{L}\p{M}]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        for m in matches {
            let word = nsString.substring(with: m.range)
            tokens.append((word, m.range))
        }

        if tokens.count < 2 { return [] }

        // Quét từng cặp từ liền kề (Bigram window)
        var i = 0
        while i < tokens.count - 1 {
            let t1 = tokens[i]
            let t2 = tokens[i + 1]

            // Chỉ xét nếu hai từ nằm sát nhau (chỉ cách nhau 1 khoảng trắng)
            let gap = t2.range.location - (t1.range.location + t1.range.length)
            if gap <= 2 {
                if let corrected = correctPhrase(t1.word, t2.word) {
                    let combinedRange = NSRange(location: t1.range.location, length: t2.range.location + t2.range.length - t1.range.location)
                    let origText = nsString.substring(with: combinedRange)
                    let repText = "\(corrected.w1) \(corrected.w2)"
                    corrections.append(SpellCorrection(
                        original: origText,
                        replacement: repText,
                        range: combinedRange,
                        explanation: corrected.reason
                    ))
                    i += 1 // Bỏ qua từ tiếp theo để tránh trùng lặp
                }
            }
            i += 1
        }

        return corrections
    }

    private static func restoreCasing(original: String, corrected: String) -> String {
        if original.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return corrected.uppercased()
        }
        if original.first?.isUppercase == true {
            return corrected.prefix(1).uppercased() + corrected.dropFirst()
        }
        return corrected.lowercased()
    }
}
