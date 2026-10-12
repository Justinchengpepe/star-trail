import Vision

@main
struct ThemeClassificationChecks {
    static func main() {
        func observation(_ label: String, _ confidence: Float) -> ThemeEvidence {
            ThemeEvidence(identifier: label, confidence: confidence)
        }
        func check(_ labels: [ThemeEvidence], _ expected: MemoryTheme, text: String = "") {
            let result = MemoryTheme.bestMatch(evidence: labels, recognizedText: text)
            precondition(result.0 == expected, "Expected \(expected), got \(result.0)")
        }
        check([observation("crowd", 0.95)], .uncertain)
        check([observation("musical_instrument", 0.93)], .uncertain)
        check([observation("paper_bag", 0.95)], .uncertain)
        check([observation("food", 0.86), observation("pizza", 0.80)], .food)
        check([observation("food", 0.59), observation("people", 0.57)], .uncertain)
        check([observation("concert", 0.78), observation("microphone", 0.64)], .concert)
        check([observation("document", 0.85)], .document, text: "演唱会门票")
        check([], .uncertain, text: "演唱会 音乐节 concert")
        check([observation("adult_cat", 0.88)], .pet)
        check([observation("cityscape", 0.88)], .city)
        print("10 theme classification checks passed")
    }
}
