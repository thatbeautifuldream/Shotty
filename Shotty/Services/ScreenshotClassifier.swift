import Foundation

struct ScreenshotTagSuggestion {
    let tags: [String]
}

struct ScreenshotClassifier {
    func suggestTags(for text: String, fileName: String = "") -> ScreenshotTagSuggestion {
        let normalized = normalize("\(fileName)\n\(text)")
        var scoredTags: [String: Int] = [:]

        for rule in suggestionRules {
            var score = 0
            var matchedTags = Set<String>()

            for signal in rule.signals where normalized.contains(signal.phrase) {
                score += signal.weight
                matchedTags.formUnion(signal.tags)
            }

            for pattern in rule.patterns where matches(pattern, in: normalized) {
                score += pattern.weight
                matchedTags.formUnion(pattern.tags)
            }

            guard score >= rule.minimumScore else { continue }

            scoredTags[rule.baseTag, default: 0] += score
            for tag in matchedTags {
                scoredTags[tag, default: 0] += max(1, score / 2)
            }
        }

        let tags = scoredTags
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }
                return left.value > right.value
            }
            .prefix(6)
            .map(\.key)

        return ScreenshotTagSuggestion(tags: tags.isEmpty ? ["untagged"] : tags)
    }

    private var suggestionRules: [Rule] {
        [
            Rule(
                baseTag: "receipt",
                minimumScore: 4,
                signals: [
                    Signal("receipt", 5), Signal("subtotal", 4), Signal("total", 3), Signal("tax", 3),
                    Signal("paid", 3), Signal("payment", 2), Signal("change", 2), Signal("cashier", 3),
                    Signal("visa", 2), Signal("mastercard", 2), Signal("store", 1)
                ],
                patterns: [
                    Pattern(#"\b(total|subtotal|tax)\s*[:\-]?\s*[$₹€£]?\s*\d+([.,]\d{2})?\b"#, 6, ["amount"]),
                    Pattern(#"\b\d{2}/\d{2}/\d{2,4}\b.*\b(total|paid)\b"#, 4)
                ]
            ),
            Rule(
                baseTag: "invoice",
                minimumScore: 4,
                signals: [
                    Signal("invoice", 7), Signal("amount due", 6), Signal("balance due", 6),
                    Signal("bill to", 5), Signal("due date", 5), Signal("invoice number", 5),
                    Signal("gstin", 4), Signal("purchase order", 4), Signal("terms", 2)
                ],
                patterns: [
                    Pattern(#"\binv(oice)?[\s#:.-]*\d+\b"#, 6, ["billing"]),
                    Pattern(#"\b(due|payable)\s*[:\-]?\s*[$₹€£]?\s*\d+([.,]\d{2})?\b"#, 5, ["billing"])
                ]
            ),
            Rule(
                baseTag: "ticket",
                minimumScore: 4,
                signals: [
                    Signal("boarding pass", 8), Signal("gate", 4), Signal("seat", 4),
                    Signal("booking", 4), Signal("reservation", 4), Signal("pnr", 5),
                    Signal("departure", 3), Signal("arrival", 3), Signal("ticket", 4),
                    Signal("event", 3), Signal("admit", 4)
                ],
                patterns: [
                    Pattern(#"\b(seat|gate)\s*[a-z]?\d{1,3}\b"#, 5, ["travel"]),
                    Pattern(#"\b[A-Z0-9]{5,8}\b.*\b(pnr|booking)\b"#, 5, ["booking"])
                ]
            ),
            Rule(
                baseTag: "code",
                minimumScore: 4,
                signals: [
                    Signal("func ", 5), Signal("struct ", 5), Signal("class ", 5), Signal("import ", 4),
                    Signal("const ", 4), Signal("let ", 3), Signal("var ", 3), Signal("return ", 3),
                    Signal("npm ", 4), Signal("git ", 4), Signal("stack trace", 6), Signal("```", 5)
                ],
                patterns: [
                    Pattern(#"(=>|==|!=|<=|>=|\{|\}|</?[a-z][^>]*>)"#, 4, ["developer"]),
                    Pattern(#"\b(function|interface|enum|protocol|extension)\s+[a-z_]"#, 5, ["developer"])
                ]
            ),
            Rule(
                baseTag: "social",
                minimumScore: 4,
                signals: [
                    Signal("repost", 5), Signal("reply", 3), Signal("quote", 3), Signal("followers", 4),
                    Signal("following", 3), Signal("posted", 2), Signal("tweet", 6), Signal("retweet", 6)
                ],
                patterns: [
                    Pattern(#"(^|\s)@[a-z0-9_]{2,15}\b"#, 5, ["handle"]),
                    Pattern(#"(^|\s)#[a-z0-9_]+\b"#, 3, ["hashtag"]),
                    Pattern(#"\b\d+[kKmM]?\s+(views|likes|reposts)\b"#, 4)
                ]
            ),
            Rule(
                baseTag: "recipe",
                minimumScore: 4,
                signals: [
                    Signal("ingredients", 7), Signal("directions", 5), Signal("preheat", 5),
                    Signal("tablespoon", 4), Signal("teaspoon", 4), Signal("servings", 4),
                    Signal("bake", 3), Signal("cook", 2), Signal("minutes", 2)
                ],
                patterns: [
                    Pattern(#"\b(tsp|tbsp|cup|cups|grams|g)\b"#, 4, ["ingredients"]),
                    Pattern(#"\b\d+\s*(min|mins|minutes|hours)\b"#, 3)
                ]
            ),
            Rule(
                baseTag: "address",
                minimumScore: 4,
                signals: [
                    Signal("street", 4), Signal("avenue", 4), Signal("road", 3), Signal("boulevard", 4),
                    Signal("suite", 3), Signal("floor", 2), Signal("postal", 3), Signal("zip", 3),
                    Signal("near", 2), Signal("landmark", 3)
                ],
                patterns: [
                    Pattern(#"\b\d{1,6}\s+[a-z0-9 .'-]+(street|st|road|rd|avenue|ave|lane|ln|drive|dr)\b"#, 7, ["place"]),
                    Pattern(#"\b\d{5,6}(-\d{4})?\b"#, 3, ["postal"])
                ]
            ),
            Rule(
                baseTag: "error",
                minimumScore: 4,
                signals: [
                    Signal("error", 5), Signal("exception", 6), Signal("failed", 5), Signal("failure", 4),
                    Signal("crash", 6), Signal("warning", 3), Signal("fatal", 6), Signal("denied", 4),
                    Signal("cannot", 3), Signal("unable to", 4), Signal("not found", 4)
                ],
                patterns: [
                    Pattern(#"\b(error|exception|fatal)\s*[:#-]\s*[a-z0-9_ -]+"#, 6, ["debug"]),
                    Pattern(#"\b(4\d\d|5\d\d)\s+(error|not found|forbidden|server)\b"#, 5, ["debug"])
                ]
            )
        ]
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func matches(_ pattern: Pattern, in text: String) -> Bool {
        text.range(of: pattern.expression, options: .regularExpression) != nil
    }
}

private struct Rule {
    let baseTag: String
    let minimumScore: Int
    let signals: [Signal]
    let patterns: [Pattern]
}

private struct Signal {
    let phrase: String
    let weight: Int
    let tags: [String]

    init(_ phrase: String, _ weight: Int, _ tags: [String] = []) {
        self.phrase = phrase
        self.weight = weight
        self.tags = tags
    }
}

private struct Pattern {
    let expression: String
    let weight: Int
    let tags: [String]

    init(_ expression: String, _ weight: Int, _ tags: [String] = []) {
        self.expression = expression
        self.weight = weight
        self.tags = tags
    }
}
