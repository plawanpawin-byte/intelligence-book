import Foundation

/// Speech recognition spells Thai numbers out ("แปดร้อยห้าสิบ"). A 3B model gets the arithmetic of converting
/// them wrong, so we turn them into digits deterministically before the model sees the text.
///
/// Only sequences containing a multiplier (สิบ ร้อย พัน หมื่น แสน ล้าน) are converted, so ordinary words that start
/// with a digit word (สามารถ, เก้าอี้, หกล้ม, มือสอง) are left alone. Colloquial forms are understood:
/// "หมื่นสอง" = 12,000, "ร้อยห้า" = 150, "พันสอง" = 1,200, "ร้อยละห้าสิบ" = 50%.
enum ThaiNumbers {
    private static let digits: [String: Int] = [
        "ศูนย์": 0, "หนึ่ง": 1, "เอ็ด": 1, "สอง": 2, "ยี่": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6, "เจ็ด": 7,
        "แปด": 8, "เก้า": 9,
    ]
    private static let multipliers: [String: Int] = [
        "สิบ": 10, "ร้อย": 100, "พัน": 1_000, "หมื่น": 10_000, "แสน": 100_000, "ล้าน": 1_000_000,
    ]
    private static let words: [String] = (Array(digits.keys) + Array(multipliers.keys)).sorted { $0.count > $1.count }

    private static let sequence: NSRegularExpression = {
        try! NSRegularExpression(pattern: "(?:" + words.joined(separator: "|") + ")+")
    }()
    private static let percent: NSRegularExpression = {
        try! NSRegularExpression(pattern: "ร้อยละ\\s*((?:" + words.joined(separator: "|") + ")+|[0-9][0-9,.]*)")
    }()
    /// A dependent vowel / tone mark (or a known word ending) that continues the previous syllable: สาม|ารถ, พัน|ธุ์.
    private static let continues: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^(?:[\\u0E30-\\u0E3A\\u0E47-\\u0E4E\\u0E32\\u0E33]|ธ|อี้|ล้ม)")
    }()

    static func convert(_ text: String) -> String {
        var text = replace(percent, in: text) { match, ns in
            let inner = ns.substring(with: match.range(at: 1))
            if let first = inner.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) { return inner + "%" }
            guard let tokens = tokenize(inner), let v = value(tokens) else { return nil }
            return v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))) + "%"
        }
        text = replace(sequence, in: text) { match, ns in
            let range = match.range
            let seq = ns.substring(with: range)
            guard let tokens = tokenize(seq), tokens.contains(where: { multipliers[$0] != nil }) else { return nil }
            let afterRange = NSRange(location: range.location + range.length, length: min(3, ns.length - range.location - range.length))
            let after = ns.substring(with: afterRange)
            if continues.firstMatch(in: after, range: NSRange(location: 0, length: (after as NSString).length)) != nil { return nil }
            let beforeStart = max(0, range.location - 6)
            let before = ns.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart))
            if before.hasSuffix("เรียบ") { return nil }
            if tokens.count == 1, tokens[0] == "พัน" || tokens[0] == "แสน" { return nil }
            if tokens[0] == "ยี่", tokens.count < 2 || tokens[1] != "สิบ" { return nil }
            guard let v = value(tokens) else { return nil }
            let formatted = v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
            let lead = range.location == 0 || ns.substring(with: NSRange(location: range.location - 1, length: 1)).first?.isWhitespace == true ? "" : " "
            let end = range.location + range.length
            let trail = end >= ns.length || ns.substring(with: NSRange(location: end, length: 1)).first?.isWhitespace == true ? "" : " "
            return lead + formatted + trail
        }
        return text
    }

    private static func replace(
        _ regex: NSRegularExpression, in text: String,
        with transform: (NSTextCheckingResult, NSString) -> String?
    ) -> String {
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(match, ns) ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func tokenize(_ seq: String) -> [String]? {
        var out: [String] = []
        var rest = Substring(seq)
        while !rest.isEmpty {
            guard let word = words.first(where: { rest.hasPrefix($0) }) else { return nil }
            out.append(word)
            rest = rest.dropFirst(word.count)
        }
        return out
    }

    private static func value(_ tokens: [String]) -> Int? {
        var million = 0
        var current = 0
        var pending: Int?
        var lastMultiplier: Int?
        for token in tokens {
            if let d = digits[token] {
                if pending != nil { return nil } // two digits in a row: not a number we understand
                pending = d
            } else if let m = multipliers[token] {
                if m == 1_000_000 {
                    let part = current + (pending ?? 0)
                    million = (million + (part == 0 ? 1 : part)) * 1_000_000
                    current = 0
                    pending = nil
                    lastMultiplier = nil
                    continue
                }
                current += (pending ?? 1) * m
                pending = nil
                lastMultiplier = m
            }
        }
        if let pending {
            if let lastMultiplier, lastMultiplier >= 100, tokens.count >= 2,
               multipliers[tokens[tokens.count - 2]] != nil, tokens.last != "เอ็ด" {
                current += pending * lastMultiplier / 10 // colloquial: หมื่นสอง = 12,000
            } else {
                current += pending
            }
        }
        return million + current
    }
}
