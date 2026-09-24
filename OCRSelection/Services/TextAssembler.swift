import CoreGraphics
import Foundation

/// What Vision's document recognition found, reduced to what `TextAssembler` needs and kept
/// free of Vision types so tests can build layouts by hand. Frames are in image pixels with
/// the origin at the top-left (y grows downwards), so the geometry reads like the screen.
struct RecognizedLayout: Equatable {
    /// A line of a paragraph, or a word of a table cell.
    struct Fragment: Equatable {
        var text: String
        var frame: CGRect
    }

    struct Paragraph: Equatable {
        /// Vision's transcript: wrapped lines already joined, hyphenation already resolved.
        var text: String
        var lines: [Fragment]
        var frame: CGRect
    }

    struct ListItem: Equatable {
        /// As printed, trailing space included ("• ", "1. ").
        var marker: String
        var text: String
        var frame: CGRect
    }

    struct List: Equatable {
        var items: [ListItem]
        var frame: CGRect
    }

    struct Cell: Equatable {
        var text: String
        var rows: ClosedRange<Int>
        var columns: ClosedRange<Int>
        var frame: CGRect
        var words: [Fragment]
        /// A line of the cell continues on the next one: the cell holds running prose.
        var hasWrappedText: Bool
    }

    struct Table: Equatable {
        var rowCount: Int
        var columnCount: Int
        var cells: [Cell]
        var frame: CGRect

        func cell(row: Int, column: Int) -> Cell? {
            cells.first { $0.rows.contains(row) && $0.columns.contains(column) }
        }
    }

    /// In reading order, including the paragraphs that make up lists and tables.
    var paragraphs: [Paragraph]
    var lists: [List] = []
    var tables: [Table] = []
}

/// Turns a recognised layout into clipboard text. The point is to undo the line wrapping
/// of the captured region: a paragraph comes out as one line, a list as one item per line,
/// a table as tab-separated rows (which paste as real tables into Numbers, Excel or Sheets).
///
/// Vision's own paragraph segmentation does most of the work; the geometry below only
/// corrects its two known mistakes. When the evidence is ambiguous, the line break is kept:
/// a stray newline is a minor annoyance, an address or a form squashed onto one line is not.
enum TextAssembler {
    static func text(from layout: RecognizedLayout, preserveLineBreaks: Bool = false) -> String {
        Assembly(layout: layout, preserveLineBreaks: preserveLineBreaks).text()
    }
}

private struct Assembly {
    typealias Fragment = RecognizedLayout.Fragment

    /// A paragraph, list or table, in reading order. Only paragraphs carry `lines`, so lists
    /// and tables are never merged with a neighbour.
    struct Block {
        var text: String
        var frame: CGRect
        var lines: [Fragment]
    }

    let layout: RecognizedLayout
    let preserveLineBreaks: Bool
    let allLines: [Fragment]
    /// Median height of a line of text: the unit every tolerance below is expressed in.
    let lineHeight: CGFloat

    init(layout: RecognizedLayout, preserveLineBreaks: Bool) {
        self.layout = layout
        self.preserveLineBreaks = preserveLineBreaks
        allLines = layout.paragraphs.flatMap(\.lines)
        let heights = allLines.map(\.frame.height).filter { $0 > 0 }.sorted()
        lineHeight = heights.isEmpty ? 1 : heights[heights.count / 2]
    }

    func text() -> String {
        var merged: [Block] = []
        for block in blocks() {
            if let previous = merged.last, continues(previous, into: block) {
                merged[merged.count - 1] = Block(
                    text: previous.text + " " + block.text,
                    frame: previous.frame.union(block.frame),
                    lines: previous.lines + block.lines
                )
            } else {
                merged.append(block)
            }
        }
        guard var text = merged.first?.text else { return "" }
        for (previous, block) in zip(merged, merged.dropFirst()) {
            // A gap taller than the spacing between lines of a paragraph separates paragraphs.
            let gap = block.frame.minY - previous.frame.maxY
            text += gap > lineHeight * 0.8 ? "\n\n" : "\n"
            text += block.text
        }
        return text
    }

    /// Lists and tables replace the paragraphs they contain, at the position of the first one.
    private func blocks() -> [Block] {
        let tables = layout.tables.filter { !isColumnLayout($0) }
        // Keeping the original line breaks means reading list items line by line too.
        let lists = preserveLineBreaks ? [] : layout.lists
        var emittedTables = Set<Int>(), emittedLists = Set<Int>()
        var blocks: [Block] = []
        for paragraph in layout.paragraphs {
            let center = CGPoint(x: paragraph.frame.midX, y: paragraph.frame.midY)
            if let index = tables.firstIndex(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(center) }) {
                if emittedTables.insert(index).inserted {
                    blocks.append(Block(text: tableText(tables[index]), frame: tables[index].frame, lines: []))
                }
                continue
            }
            if let index = lists.firstIndex(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(center) }) {
                if emittedLists.insert(index).inserted {
                    blocks.append(Block(text: listText(lists[index]), frame: lists[index].frame, lines: []))
                }
                continue
            }
            let text = preserveLineBreaks
                ? paragraph.lines.map(\.text).joined(separator: "\n")
                : paragraphText(paragraph)
            blocks.append(Block(text: text, frame: paragraph.frame, lines: paragraph.lines))
        }
        // Vision lists the paragraphs inside lists and tables too, so this should not happen;
        // if it ever does, place the structure by its top edge rather than lose its text.
        let leftovers = tables.indices.filter { !emittedTables.contains($0) }
            .map { Block(text: tableText(tables[$0]), frame: tables[$0].frame, lines: []) }
            + lists.indices.filter { !emittedLists.contains($0) }
            .map { Block(text: listText(lists[$0]), frame: lists[$0].frame, lines: []) }
        for block in leftovers where !block.text.isEmpty {
            let index = blocks.firstIndex { $0.frame.minY > block.frame.minY } ?? blocks.endIndex
            blocks.insert(block, at: index)
        }
        return blocks
    }

    // MARK: - Line breaks

    /// Right edge of the text column `line` belongs to: the widest line of the capture that
    /// starts at the same left edge.
    private func columnRight(for line: Fragment) -> CGFloat {
        allLines
            .filter { abs($0.frame.minX - line.frame.minX) < lineHeight }
            .map(\.frame.maxX)
            .max() ?? line.frame.maxX
    }

    /// Would the first word of `next` have fitted at the end of `line`? If it would, the line
    /// did not end for lack of room: the break was deliberate (poem, address, `<br>`).
    private func firstWordFits(after line: Fragment, next: Fragment) -> Bool {
        // A word hyphenated across lines means the line was full, whatever the geometry says.
        guard !line.text.hasSuffix("-") else { return false }
        guard let firstWord = next.text.split(separator: " ").first else { return false }
        // Only the line's box is known, so estimate the word's width from its share of characters.
        let wordWidth = next.frame.width * CGFloat(firstWord.count) / CGFloat(next.text.count)
        let spaceWidth = lineHeight * 0.35
        return line.frame.maxX + spaceWidth + wordWidth < columnRight(for: line) - lineHeight * 0.5
    }

    /// Vision's transcript, except where it joined lines that were broken on purpose (it
    /// runs the lines of a poem together, for instance).
    private func paragraphText(_ paragraph: RecognizedLayout.Paragraph) -> String {
        let lines = paragraph.lines
        let hardBreaks = Set(zip(lines, lines.dropFirst()).enumerated().compactMap { index, pair in
            firstWordFits(after: pair.0, next: pair.1) ? index : nil
        })
        guard !hardBreaks.isEmpty else { return paragraph.text }

        // Cut the transcript rather than rebuild it from the lines, so Vision's joins (and its
        // hyphenation fixes) survive. Each line is located after the previous one; a line
        // ending in a hyphen may have been joined to the next word, so it is looked up without it.
        let transcript = paragraph.text
        var cursor = transcript.startIndex
        var cuts: [String.Index] = []
        for (index, line) in lines.enumerated() {
            var needle = line.text
            if needle.hasSuffix("-") { needle.removeLast() }
            guard let found = transcript.range(of: needle, range: cursor..<transcript.endIndex) else {
                // The transcript doesn't line up with its lines: fall back to the lines themselves.
                return lines.enumerated().map { index, line in
                    line.text + (index == lines.count - 1 ? "" : hardBreaks.contains(index) ? "\n" : " ")
                }.joined()
            }
            if index > 0, hardBreaks.contains(index - 1) {
                cuts.append(found.lowerBound)
            }
            cursor = found.upperBound
        }
        var text = ""
        var start = transcript.startIndex
        for cut in cuts {
            text += transcript[start..<cut].trimmingCharacters(in: .whitespaces)
            text += "\n"
            start = cut
        }
        return text + transcript[start...]
    }

    /// Vision sometimes ends a paragraph after a line that was merely wrapped, typically one
    /// ending a sentence. Rejoin only running text (one side spans several lines), at normal
    /// line spacing, same left edge, same text size, when the next word could not have fitted.
    /// Short single lines such as an address or a form stay one per line.
    private func continues(_ previous: Block, into next: Block) -> Bool {
        guard !preserveLineBreaks,
              let last = previous.lines.last, let first = next.lines.first,
              previous.lines.count > 1 || next.lines.count > 1,
              last.frame.height > 0, first.frame.height > 0
        else { return false }
        let gap = next.frame.minY - previous.frame.maxY
        let indent = first.frame.minX - min(previous.frame.minX, next.frame.minX)
        let sizeRatio = max(first.frame.height, last.frame.height) / min(first.frame.height, last.frame.height)
        return gap < lineHeight * 0.8
            && gap > -lineHeight * 0.3
            && indent < lineHeight * 0.8
            && sizeRatio < 1.35
            && !firstWordFits(after: last, next: first)
    }

    // MARK: - Lists

    /// One item per line, marker kept, nested items indented with tabs.
    private func listText(_ list: RecognizedLayout.List) -> String {
        // Each distinct left edge is one nesting level.
        var levels: [CGFloat] = []
        for x in list.items.map(\.frame.minX).sorted() where levels.last.map({ x - $0 > lineHeight }) ?? true {
            levels.append(x)
        }
        return list.items.map { item in
            let depth = levels.lastIndex { $0 <= item.frame.minX } ?? 0
            return String(repeating: "\t", count: depth) + item.marker + item.text
        }.joined(separator: "\n")
    }

    // MARK: - Tables

    /// Vision reports side-by-side text columns as a table. Real tables hold short values,
    /// at most one column of longer text (a glossary's definitions): when wrapped prose fills
    /// most cells across several columns, read the columns as paragraphs instead.
    private func isColumnLayout(_ table: RecognizedLayout.Table) -> Bool {
        let filled = table.cells.filter { !$0.text.isEmpty }
        let prose = filled.filter(\.hasWrappedText)
        return Set(prose.map(\.columns.lowerBound)).count >= 2 && prose.count * 2 >= filled.count
    }

    /// Tab-separated rows, one line each. Vision's grid is reliable, but it sometimes files the
    /// words of two adjacent cells under one of them and leaves the other empty (seen on tables
    /// without borders). Such words are moved into the empty column they sit in. Cells Vision
    /// reports as merged (spanning several columns or rows) are left alone.
    private func tableText(_ table: RecognizedLayout.Table) -> String {
        let columnCount = table.columnCount
        var columnSpans = [ClosedRange<CGFloat>?](repeating: nil, count: columnCount)
        for cell in table.cells where cell.columns.count == 1 && cell.columns.lowerBound < columnCount {
            let column = cell.columns.lowerBound
            let span = cell.frame.minX...cell.frame.maxX
            columnSpans[column] = columnSpans[column].map {
                min($0.lowerBound, span.lowerBound)...max($0.upperBound, span.upperBound)
            } ?? span
        }

        return (0..<table.rowCount).map { row in
            var texts = [String](repeating: "", count: columnCount)
            var words = [[Fragment]](repeating: [], count: columnCount)
            var isEmptyColumn = [Bool](repeating: false, count: columnCount)
            for column in 0..<columnCount {
                guard let cell = table.cell(row: row, column: column) else {
                    isEmptyColumn[column] = true
                    continue
                }
                // Covered by a merged cell anchored in another row or column.
                guard cell.rows.lowerBound == row, cell.columns.lowerBound == column else { continue }
                texts[column] = cell.text.replacingOccurrences(of: "\n", with: " ")
                isEmptyColumn[column] = cell.text.isEmpty
                if cell.columns.count == 1 { words[column] = cell.words }
            }

            var strays = [[Fragment]](repeating: [], count: columnCount)
            for column in 0..<columnCount where !words[column].isEmpty {
                var kept: [Fragment] = []
                for word in words[column] {
                    if let target = columnSpans.firstIndex(where: { $0?.contains(word.frame.midX) == true }),
                       target != column, isEmptyColumn[target] {
                        strays[target].append(word)
                    } else {
                        kept.append(word)
                    }
                }
                if kept.count < words[column].count {
                    texts[column] = kept.map(\.text).joined(separator: " ")
                }
            }
            for column in 0..<columnCount where !strays[column].isEmpty {
                texts[column] = strays[column].map(\.text).joined(separator: " ")
            }
            return texts.joined(separator: "\t")
        }.joined(separator: "\n")
    }
}
