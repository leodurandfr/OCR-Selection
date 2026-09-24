import CoreGraphics
import Testing
@testable import OCRSelection

/// Layouts are built by hand on a simple grid: every character is 10 px wide, a line is
/// 20 px tall and lines of a paragraph are 28 px apart, so the widths below read as
/// character counts.
struct TextAssemblerTests {
    @Test func keepsVisionTranscriptForWrappedParagraph() {
        let paragraph = paragraph([
            line("The quick brown fox jumps over the lazy", row: 0),
            line("dog and keeps running across the field", row: 1),
            line("until dusk.", row: 2),
        ])
        #expect(TextAssembler.text(from: RecognizedLayout(paragraphs: [paragraph])) ==
            "The quick brown fox jumps over the lazy dog and keeps running across the field until dusk.")
    }

    @Test func splitsLinesVisionJoinedOnPurpose() {
        let reference = paragraph([line("A much wider line of text that sets the column width", row: 0)])
        let poem = paragraph([
            line("Roses are red,", row: 2),
            line("Violets are blue,", row: 3),
            line("Sugar is sweet,", row: 4),
            line("And so are you.", row: 5),
        ])
        #expect(TextAssembler.text(from: RecognizedLayout(paragraphs: [reference, poem])) ==
            "A much wider line of text that sets the column width\n\nRoses are red,\nViolets are blue,\nSugar is sweet,\nAnd so are you.")
    }

    @Test func splittingKeepsVisionHyphenationFix() {
        let paragraph = paragraph(
            [
                line("Les retours à la ligne au-", row: 0),
                line("tomatiques deviennent des", row: 1),
                line("sauts.", row: 2),
                line("Signé", row: 3),
            ],
            text: "Les retours à la ligne automatiques deviennent des sauts. Signé"
        )
        #expect(TextAssembler.text(from: RecognizedLayout(paragraphs: [paragraph])) ==
            "Les retours à la ligne automatiques deviennent des sauts.\nSigné")
    }

    @Test func rejoinsParagraphSplitAfterFullWidthSentence() {
        let first = paragraph([line("It was a bright cold day, the clocks struck.", row: 0)])
        let second = paragraph([
            line("Winston Smith slipped quickly through the", row: 1),
            line("glass doors.", row: 2),
        ])
        #expect(TextAssembler.text(from: RecognizedLayout(paragraphs: [first, second])) ==
            "It was a bright cold day, the clocks struck. Winston Smith slipped quickly through the glass doors.")
    }

    @Test func keepsShortSingleLinesApart() {
        let lines = ["Name: Jane Appleseed", "Email: jane@example.com", "Phone: +33 6 12 34 56 78"]
        let layout = RecognizedLayout(paragraphs: lines.enumerated().map { paragraph([line($1, row: $0)]) })
        #expect(TextAssembler.text(from: layout) == lines.joined(separator: "\n"))
    }

    @Test func blankLineBetweenSpacedParagraphs() {
        let layout = RecognizedLayout(paragraphs: [
            paragraph([line("First paragraph.", row: 0)]),
            paragraph([line("Second paragraph.", row: 2)]),
        ])
        #expect(TextAssembler.text(from: layout) == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func listsOneItemPerLineWithNesting() {
        let items = [
            item("An Apple ID with two-factor authentication", x: 20, row: 2),
            item("enrolled in the developer program", x: 60, row: 3),
            item("Coffee.", x: 20, row: 4),
        ]
        let layout = RecognizedLayout(
            paragraphs: [paragraph([line("Bring:", row: 0)])] + items.map { paragraph([line($0.marker + $0.text, x: $0.frame.minX, row: row(of: $0))]) },
            lists: [RecognizedLayout.List(items: items, frame: items.map(\.frame).reduce(items[0].frame) { $0.union($1) })]
        )
        #expect(TextAssembler.text(from: layout) ==
            "Bring:\n\n• An Apple ID with two-factor authentication\n\t• enrolled in the developer program\n• Coffee.")
    }

    @Test func tableRowsAreTabSeparated() {
        let table = table(rows: [["Plan", "Price"], ["Pro", "$9.99"]], columnEdges: [0, 100, 200])
        #expect(TextAssembler.text(from: table) == "Plan\tPrice\nPro\t$9.99")
    }

    @Test func movesWordsFiledUnderTheWrongCellIntoTheEmptyColumn() {
        // Vision put both numbers in the Q1 cell and left Q2 empty (seen on borderless tables).
        var layout = table(rows: [["Region", "Q1", "Q2"], ["North America", "1,204 1,388", ""]], columnEdges: [0, 200, 300, 400])
        let misfiled = layout.tables[0].cells.firstIndex { $0.text == "1,204 1,388" }!
        layout.tables[0].cells[misfiled].words = [
            .init(text: "1,204", frame: CGRect(x: 225, y: 28, width: 50, height: 20)),
            .init(text: "1,388", frame: CGRect(x: 325, y: 28, width: 50, height: 20)),
        ]
        #expect(TextAssembler.text(from: layout) == "Region\tQ1\tQ2\nNorth America\t1,204\t1,388")
    }

    @Test func leavesMergedCellsAlone() {
        var layout = table(rows: [["Storage", "", "Price"], ["Base", "Max", "1 €"]], columnEdges: [0, 100, 200, 300])
        // "Storage" spans the first two columns.
        layout.tables[0].cells.removeAll { $0.rows == 0...0 && $0.columns == 1...1 }
        let storage = layout.tables[0].cells.firstIndex { $0.text == "Storage" }!
        layout.tables[0].cells[storage].columns = 0...1
        layout.tables[0].cells[storage].frame = CGRect(x: 0, y: 0, width: 200, height: 20)
        layout.tables[0].cells[storage].words = [.init(text: "Storage", frame: CGRect(x: 120, y: 0, width: 70, height: 20))]
        #expect(TextAssembler.text(from: layout) == "Storage\t\tPrice\nBase\tMax\t1 €")
    }

    @Test func readsSideBySideProseColumnsAsParagraphs() {
        let left = paragraph([line("The first column wraps onto", row: 0), line("a second line.", row: 1)])
        let right = paragraph([line("The second column also", x: 300, row: 0), line("wraps here.", x: 300, row: 1)])
        let cells = [left, right].enumerated().map { index, paragraph in
            RecognizedLayout.Cell(
                text: paragraph.text, rows: 0...0, columns: index...index, frame: paragraph.frame,
                words: [], hasWrappedText: true
            )
        }
        let layout = RecognizedLayout(
            paragraphs: [left, right],
            tables: [RecognizedLayout.Table(rowCount: 1, columnCount: 2, cells: cells, frame: left.frame.union(right.frame))]
        )
        #expect(TextAssembler.text(from: layout) ==
            "The first column wraps onto a second line.\nThe second column also wraps here.")
    }

    @Test func neverBreaksAfterAHyphenatedLine() {
        // The wide line makes "ligne au-" look short, but a hyphen at the end means it wrapped.
        let wide = paragraph([line("A much wider line of text that sets the column width", row: 0)])
        let hyphenated = paragraph(
            [line("Les retours à la ligne au-", row: 2), line("tomatiques.", row: 3)],
            text: "Les retours à la ligne automatiques."
        )
        #expect(TextAssembler.text(from: RecognizedLayout(paragraphs: [wide, hyphenated])) ==
            "A much wider line of text that sets the column width\n\nLes retours à la ligne automatiques.")
    }

    @Test func glossaryWithWrappedDefinitionsStaysATable() {
        var layout = table(rows: [["Kerning", "Space between two letters"], ["Leading", "Space between lines"]], columnEdges: [0, 100, 300])
        for index in layout.tables[0].cells.indices where layout.tables[0].cells[index].columns == 1...1 {
            layout.tables[0].cells[index].hasWrappedText = true
        }
        #expect(TextAssembler.text(from: layout) == "Kerning\tSpace between two letters\nLeading\tSpace between lines")
    }

    @Test func keepsATableNoParagraphPointsAt() {
        var layout = table(rows: [["Plan", "Price"]], columnEdges: [0, 100, 200])
        layout.paragraphs = [paragraph([line("Pricing", row: -2)])]
        #expect(TextAssembler.text(from: layout) == "Pricing\n\nPlan\tPrice")
    }

    @Test func preserveLineBreaksKeepsEveryVisualLine() {
        let items = [item("Run the install command and wait for the", x: 20, row: 1)]
        let layout = RecognizedLayout(
            paragraphs: [
                paragraph([line("The quick brown fox jumps over the lazy", row: 0)]),
                paragraph(
                    [line("• Run the install command and wait for the", x: 20, row: 1), line("progress bar.", x: 36, row: 2)],
                    text: "• Run the install command and wait for the progress bar."
                ),
            ],
            lists: [RecognizedLayout.List(items: items, frame: CGRect(x: 20, y: 28, width: 420, height: 48))]
        )
        #expect(TextAssembler.text(from: layout, preserveLineBreaks: true) ==
            "The quick brown fox jumps over the lazy\n• Run the install command and wait for the\nprogress bar.")
    }

    @Test func emptyLayoutGivesEmptyText() {
        #expect(TextAssembler.text(from: RecognizedLayout(paragraphs: [])) == "")
    }
}

// MARK: - Fixtures

private let characterWidth: CGFloat = 10
private let lineHeight: CGFloat = 20
private let linePitch: CGFloat = 28

private func line(_ text: String, x: CGFloat = 0, row: Int) -> RecognizedLayout.Fragment {
    RecognizedLayout.Fragment(
        text: text,
        frame: CGRect(x: x, y: CGFloat(row) * linePitch, width: CGFloat(text.count) * characterWidth, height: lineHeight)
    )
}

private func paragraph(_ lines: [RecognizedLayout.Fragment], text: String? = nil) -> RecognizedLayout.Paragraph {
    RecognizedLayout.Paragraph(
        text: text ?? lines.map(\.text).joined(separator: " "),
        lines: lines,
        frame: lines.dropFirst().reduce(lines[0].frame) { $0.union($1.frame) }
    )
}

private func item(_ text: String, x: CGFloat, row: Int) -> RecognizedLayout.ListItem {
    let marker = "• "
    return RecognizedLayout.ListItem(marker: marker, text: text, frame: line(marker + text, x: x, row: row).frame)
}

private func row(of item: RecognizedLayout.ListItem) -> Int {
    Int(item.frame.minY / linePitch)
}

/// A table with one single-column, single-row cell per value; `columnEdges` has one more
/// entry than there are columns. Each non-empty cell is also a paragraph, as Vision reports it.
private func table(rows: [[String]], columnEdges: [CGFloat]) -> RecognizedLayout {
    var cells: [RecognizedLayout.Cell] = []
    var paragraphs: [RecognizedLayout.Paragraph] = []
    for (rowIndex, values) in rows.enumerated() {
        for (column, value) in values.enumerated() {
            let frame = CGRect(
                x: columnEdges[column], y: CGFloat(rowIndex) * linePitch,
                width: columnEdges[column + 1] - columnEdges[column], height: lineHeight
            )
            let words = value.split(separator: " ").map { RecognizedLayout.Fragment(text: String($0), frame: frame) }
            cells.append(RecognizedLayout.Cell(
                text: value, rows: rowIndex...rowIndex, columns: column...column, frame: frame,
                words: words, hasWrappedText: false
            ))
            if !value.isEmpty {
                paragraphs.append(paragraph([RecognizedLayout.Fragment(text: value, frame: frame)]))
            }
        }
    }
    let frame = CGRect(
        x: columnEdges[0], y: 0,
        width: columnEdges[columnEdges.count - 1] - columnEdges[0], height: CGFloat(rows.count) * linePitch
    )
    return RecognizedLayout(
        paragraphs: paragraphs,
        tables: [RecognizedLayout.Table(rowCount: rows.count, columnCount: columnEdges.count - 1, cells: cells, frame: frame)]
    )
}
