import CoreGraphics
import Foundation

/// Turns recognised text fragments into clipboard text. The point is to undo the line
/// wrapping of the captured region: a paragraph comes out as one line, a list as one item
/// per line (nesting as tabs), a table as tab-separated rows (which paste as real tables
/// into Numbers, Excel or Sheets), side-by-side columns one after the other.
///
/// The structure comes from the geometry alone. Whitespace running across the whole area
/// separates paragraphs; whitespace running down it separates columns or table cells, and
/// columns are read as text or as a table depending on how their lines wrap and line up.
/// Within a column, a line is joined to the next only on evidence that it wrapped: the next
/// word would not have fitted after it. When the evidence is ambiguous, the line break is
/// kept: a stray newline is a minor annoyance, an address or a form on one line is not.
enum TextAssembler {
    static func text(from layout: RecognizedLayout, preserveLineBreaks: Bool = false) -> String {
        Assembly(layout: layout, preserveLineBreaks: preserveLineBreaks).text()
    }
}

private struct Assembly {
    typealias Fragment = RecognizedLayout.Fragment
    typealias Row = [Fragment]

    /// Text in reading order, with the area it came from.
    struct Block {
        var text: String
        var frame: CGRect
        /// The paragraph spacing of the region the block was read in: a wider gap above it
        /// is a blank line.
        var paragraphGap: CGFloat
    }

    /// Horizontal extent a line may take its column width from: the column it sits in, so
    /// that a title spanning two columns does not widen the left one.
    typealias Bounds = ClosedRange<CGFloat>

    let fragments: [Fragment]
    let preserveLineBreaks: Bool
    /// Median height of a line of text: the unit every tolerance below is expressed in.
    let lineHeight: CGFloat

    init(layout: RecognizedLayout, preserveLineBreaks: Bool) {
        self.preserveLineBreaks = preserveLineBreaks
        fragments = layout.fragments.filter {
            $0.frame.width > 0 && $0.frame.height > 0 && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        lineHeight = Self.median(fragments.map(\.frame.height)) ?? 1
    }

    func text() -> String {
        guard !fragments.isEmpty else { return "" }
        let all = Self.frame(of: fragments)
        let blocks = blocks(of: fragments, within: all.minX...all.maxX, paragraphGap: paragraphGap(of: fragments))
            .filter { !$0.text.isEmpty }
        guard var text = blocks.first?.text else { return "" }
        for (previous, block) in zip(blocks, blocks.dropFirst()) {
            text += block.frame.minY - previous.frame.maxY > block.paragraphGap ? "\n\n" : "\n"
            text += block.text
        }
        return text
    }

    /// Vertical whitespace taller than this separates paragraphs: above the usual spacing
    /// between the lines of `fragments`, so double-spaced text is not split at every line.
    private func paragraphGap(of fragments: [Fragment]) -> CGFloat {
        let rows = Self.rows(of: fragments)
        let gaps = zip(rows, rows.dropFirst()).map { max(0, Self.frame(of: $1).minY - Self.frame(of: $0).maxY) }
        let lineGap = Self.median(gaps) ?? 0
        return max(lineHeight * 0.8, min(lineGap + lineHeight * 0.5, lineHeight * 1.5))
    }

    // MARK: - Regions

    /// Recursive XY cut. Whitespace across the whole area splits it into stacked bands,
    /// whitespace down the whole area into columns; what neither splits is a run of rows.
    private func blocks(of fragments: [Fragment], within bounds: Bounds, paragraphGap: CGFloat) -> [Block] {
        let bands = Self.split(fragments, minGap: paragraphGap, along: \.minY, \.maxY)
        if bands.count > 1 {
            return bands.flatMap { blocks(of: $0, within: bounds, paragraphGap: paragraphGap) }
        }
        let columns = Self.split(fragments, minGap: gutterWidth, along: \.minX, \.maxX)
        if columns.count > 1 {
            let columnBounds = Self.columnBounds(columns, within: bounds)
            if isColumnLayout(columns, bounds: columnBounds) {
                // Each column keeps its own line spacing: the rows of two columns interleave.
                return zip(columns, columnBounds).flatMap { blocks(of: $0, within: $1, paragraphGap: self.paragraphGap(of: $0)) }
            }
            return [tableBlock(columns, bounds: columnBounds, paragraphGap: paragraphGap)]
        }
        // No whitespace cuts the whole area, but it can still hold a table or columns between
        // two lines of text: group the rows that share a gutter and cut each group again.
        let rows = Self.rows(of: fragments)
        let groups = rowGroups(rows, bounds: bounds)
        guard groups.count > 1 else {
            return [linesBlock(rows, bounds: bounds, paragraphGap: paragraphGap)]
        }
        return groups.flatMap { group in
            group.hasGutter
                ? blocks(of: group.rows.flatMap { $0 }, within: bounds, paragraphGap: paragraphGap)
                : [linesBlock(group.rows, bounds: bounds, paragraphGap: paragraphGap)]
        }
    }

    /// Wider than the space between two words, narrower than the gap between columns.
    private var gutterWidth: CGFloat { lineHeight * 1.2 }

    private struct RowGroup {
        var rows: [Row]
        var hasGutter: Bool
    }

    /// Consecutive rows, grouped by whether vertical whitespace runs through all of them.
    /// A full-width line ends a group of columns; a line inside one column does not.
    private func rowGroups(_ rows: [Row], bounds: Bounds) -> [RowGroup] {
        var groups: [RowGroup] = []
        for row in rows {
            if let last = groups.last {
                let fits = last.hasGutter
                    ? hasGutter(last.rows.flatMap { $0 } + row)
                    : !hasGutter(row)
                if fits {
                    groups[groups.count - 1].rows.append(row)
                    continue
                }
            }
            var group = RowGroup(rows: [row], hasGutter: hasGutter(row))
            // A column that starts a line higher than its neighbour leaves its first line in the
            // text above: take it back when it is narrow enough and runs on into the column.
            if group.hasGutter, let previous = groups.last, !previous.hasGutter,
               let line = previous.rows.last, line.count == 1, hasGutter(line + row),
               let below = row.first(where: { Self.overlapsHorizontally($0.frame, line[0].frame) }),
               wraps(line[0], into: below, bounds: bounds.lowerBound...max(
                   bounds.lowerBound,
                   row.filter { $0.frame.minX > below.frame.maxX }.map(\.frame.minX).min() ?? bounds.upperBound
               )) {
                groups[groups.count - 1].rows.removeLast()
                if groups[groups.count - 1].rows.isEmpty { groups.removeLast() }
                group.rows.insert(line, at: 0)
            }
            groups.append(group)
        }
        return groups
    }

    private func hasGutter(_ fragments: [Fragment]) -> Bool {
        Self.split(fragments, minGap: gutterWidth, along: \.minX, \.maxX).count > 1
    }

    /// Side-by-side text reads column after column; anything else that whitespace divides
    /// into columns is a table.
    ///
    /// A table is laid out in rows: once the wrapped part of each cell is put back into its
    /// row, most rows hold cells of several columns, where the columns of a page only line up
    /// here and there. A text column wraps most of its lines into the next one, where a table
    /// holds short values and at most one column of longer text (a glossary). Two text
    /// columns are an article; a single one is still a page (main text beside a sidebar) when
    /// its text runs on beside the other columns' text, since the wrapped part of a table
    /// cell has its line to itself, the other cells of its row being single lines.
    private func isColumnLayout(_ columns: [[Fragment]], bounds: [Bounds]) -> Bool {
        let rows = tableRows(columns, bounds: bounds, joinWrappedCells: true)
        let rowsAcrossColumns = rows.filter { $0.filter { !$0.isEmpty }.count > 1 }.count
        if Double(rowsAcrossColumns) < Double(rows.count) * 0.6 { return true }

        var textColumns = 0, continuations = 0, besideOtherText = 0
        for (index, (column, bounds)) in zip(columns, bounds).enumerated() {
            let lines = Self.rows(of: column).map(Self.line)
            guard lines.count > 1 else { continue }
            let wrapped = zip(lines, lines.dropFirst()).filter { wraps($0, into: $1, bounds: bounds) }.map(\.1)
            guard wrapped.count * 2 >= lines.count - 1 else { continue }
            textColumns += 1
            let others = columns.indices.filter { $0 != index }.flatMap { columns[$0] }
            continuations += wrapped.count
            besideOtherText += wrapped.filter { line in others.contains { Self.shareARow($0.frame, line.frame) } }.count
        }
        return textColumns >= 2 || (textColumns == 1 && besideOtherText * 2 > continuations)
    }

    // MARK: - Text

    /// Rows of running text: paragraphs and lists.
    private func linesBlock(_ rows: [Row], bounds: Bounds, paragraphGap: CGFloat) -> Block {
        let lines = rows.map(Self.line)
        let frame = Self.frame(of: lines)
        if preserveLineBreaks {
            return Block(text: lines.map(\.text).joined(separator: "\n"), frame: frame, paragraphGap: paragraphGap)
        }
        let markers = listMarkers(lines)
        let levels = markers.indices.filter { markers[$0] != nil }.map { lines[$0].frame.minX }.sorted()
            .reduce(into: [CGFloat]()) { levels, x in
                // Each distinct left edge of a marker is one nesting level.
                if levels.last.map({ x - $0 > lineHeight }) ?? true { levels.append(x) }
            }
        var text = ""
        /// Where the text of the list item being read starts: its continuation lines hang there.
        var itemTextX: CGFloat?
        for (index, line) in lines.enumerated() {
            if let marker = markers[index] {
                let depth = levels.lastIndex { $0 <= line.frame.minX + lineHeight * 0.5 } ?? 0
                if index > 0 { text += "\n" }
                text += String(repeating: "\t", count: depth) + line.text
                itemTextX = line.frame.minX + line.frame.width * CGFloat(marker.count) / CGFloat(line.text.count)
                continue
            }
            guard index > 0 else {
                text = line.text
                continue
            }
            let previous = lines[index - 1]
            if let x = itemTextX, abs(line.frame.minX - x) < lineHeight * 0.8 {
                // A list item running onto the next line, indented under its text.
                text = wraps(previous, into: line, bounds: bounds, checkIndent: false, nextIsListItem: false)
                    ? Self.joined(text, line.text)
                    : text + "\n" + line.text
                continue
            }
            itemTextX = nil
            text = wraps(previous, into: line, bounds: bounds, nextIsListItem: false)
                ? Self.joined(text, line.text)
                : text + "\n" + line.text
        }
        return Block(text: text, frame: frame, paragraphGap: paragraphGap)
    }

    /// The list marker opening each line, if it opens a list item. A dash or an asterisk
    /// also starts a line of prose that wrapped just before it, so it only counts when at
    /// least two lines start with one.
    private func listMarkers(_ lines: [Fragment]) -> [Substring?] {
        let markers = lines.map { Self.listMarker($0.text) }
        let dashed = markers.filter { $0.map(Self.isDash) == true }.count
        return markers.map { marker in marker.map(Self.isDash) == true && dashed < 2 ? nil : marker }
    }

    /// Did `line` end only because the column ran out of room, so that `next` continues it?
    ///
    /// The next word must not have fitted at the end of the line, and the line must read as
    /// running text: the next line goes on in lower case, or the line is a long one whose
    /// width another line of the column confirms. A line that is the only one that wide sets
    /// the column width itself, so it proves nothing about wrapping (an address, a form).
    /// `nextIsListItem` defaults to reading only unambiguous markers (bullets, numbers).
    private func wraps(
        _ line: Fragment, into next: Fragment, bounds: Bounds, checkIndent: Bool = true, nextIsListItem: Bool? = nil
    ) -> Bool {
        // A change of type size (a heading). Box heights follow the glyphs: descenders,
        // accents and brackets make one line of the same font up to ~1.4× taller than another.
        let sizeRatio = max(line.frame.height, next.frame.height) / min(line.frame.height, next.frame.height)
        let isListItem = nextIsListItem ?? (Self.listMarker(next.text).map(Self.isDash) == false)
        guard sizeRatio < 1.6, !isListItem else { return false }
        // An indented line starts a paragraph (or a quote); the first line of an indented
        // paragraph is followed by lines further left, which is fine.
        if checkIndent, next.frame.minX - line.frame.minX > lineHeight * 0.8 { return false }
        // A word hyphenated across lines means the line was full, whatever the geometry says.
        if Self.endsWithHyphen(line.text) { return true }
        guard !firstWordFits(after: line, next: next, bounds: bounds) else { return false }
        return Self.startsInLowercase(next.text)
            || (Self.wordCount(line.text) >= 4 && rightEdgeIsConfirmed(line, bounds: bounds))
    }

    /// Would the first word of `next` have fitted at the end of `line`? If it would, the line
    /// did not end for lack of room: the break was deliberate (poem, address, `<br>`).
    private func firstWordFits(after line: Fragment, next: Fragment, bounds: Bounds) -> Bool {
        guard let firstWord = next.text.split(separator: " ").first else { return false }
        // Only the line's box is known, so estimate the word's width from its share of characters.
        let wordWidth = next.frame.width * CGFloat(firstWord.count) / CGFloat(next.text.count)
        let spaceWidth = lineHeight * 0.35
        return line.frame.maxX + spaceWidth + wordWidth < columnRight(for: line, bounds: bounds) - lineHeight * 0.5
    }

    /// Lines of the capture that share `line`'s left edge and stay within its column.
    private func columnLines(of line: Fragment, bounds: Bounds) -> [Fragment] {
        fragments.filter {
            abs($0.frame.minX - line.frame.minX) < lineHeight && $0.frame.maxX <= bounds.upperBound + lineHeight * 0.5
        }
    }

    /// Right edge of the text column `line` belongs to: its widest line.
    private func columnRight(for line: Fragment, bounds: Bounds) -> CGFloat {
        max(line.frame.maxX, columnLines(of: line, bounds: bounds).map(\.frame.maxX).max() ?? 0)
    }

    /// Does another line of the column reach about as far right? Ragged-right text ends its
    /// lines within a word or two of the edge. The fragments `line` was read from, on its
    /// own row, do not count.
    private func rightEdgeIsConfirmed(_ line: Fragment, bounds: Bounds) -> Bool {
        columnLines(of: line, bounds: bounds).contains {
            !Self.shareARow($0.frame, line.frame) && $0.frame.maxX >= line.frame.maxX - lineHeight * 3
        }
    }

    // MARK: - Tables

    /// Tab-separated rows, one line each.
    private func tableBlock(_ columns: [[Fragment]], bounds: [Bounds], paragraphGap: CGFloat) -> Block {
        let text = tableRows(columns, bounds: bounds, joinWrappedCells: !preserveLineBreaks).map { row in
            row.map { cell in cell.map(\.text).reduce("") { $0.isEmpty ? $1 : Self.joined($0, $1) } }
                .joined(separator: "\t")
        }.joined(separator: "\n")
        return Block(text: text, frame: Self.frame(of: columns.flatMap { $0 }), paragraphGap: paragraphGap)
    }

    /// The fragments of each cell, row by row. With `joinWrappedCells`, a line holding only
    /// the wrapped part of some cells (not every column filled, each fragment continuing the
    /// cell above it) is put back into the row above.
    private func tableRows(_ columns: [[Fragment]], bounds: [Bounds], joinWrappedCells: Bool) -> [[[Fragment]]] {
        // Columns are separated by whitespace, so each fragment's centre falls in one span.
        let spans = columns.map { Self.frame(of: $0) }
        func column(of fragment: Fragment) -> Int {
            spans.firstIndex { $0.minX <= fragment.frame.midX && fragment.frame.midX <= $0.maxX } ?? 0
        }
        var rows: [[[Fragment]]] = []
        for visualRow in Self.rows(of: columns.flatMap { $0 }) {
            var row = [[Fragment]](repeating: [], count: columns.count)
            for fragment in visualRow { row[column(of: fragment)].append(fragment) }
            if joinWrappedCells, let previous = rows.last,
               row.filter({ !$0.isEmpty }).count < columns.count,
               row.indices.allSatisfy({ index in
                   guard let fragment = row[index].first else { return true }
                   guard row[index].count == 1, let above = previous[index].last else { return false }
                   return wraps(above, into: fragment, bounds: bounds[index])
               }) {
                for index in row.indices { rows[rows.count - 1][index] += row[index] }
            } else {
                rows.append(row)
            }
        }
        return rows
    }

    // MARK: - Geometry

    /// Groups fragments separated by a gap wider than `minGap` along one axis, in order.
    private static func split(
        _ fragments: [Fragment], minGap: CGFloat, along start: KeyPath<CGRect, CGFloat>, _ end: KeyPath<CGRect, CGFloat>
    ) -> [[Fragment]] {
        var groups: [[Fragment]] = []
        var reach = -CGFloat.infinity
        for fragment in fragments.sorted(by: { $0.frame[keyPath: start] < $1.frame[keyPath: start] }) {
            if groups.isEmpty || fragment.frame[keyPath: start] - reach > minGap {
                groups.append([fragment])
            } else {
                groups[groups.count - 1].append(fragment)
            }
            reach = max(reach, fragment.frame[keyPath: end])
        }
        return groups
    }

    /// Fragments on the same visual line, top to bottom, each row left to right.
    private static func rows(of fragments: [Fragment]) -> [Row] {
        var rows: [Row] = []
        for fragment in fragments.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let last = rows.last, shareARow(frame(of: last), fragment.frame) {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    /// Do the two boxes overlap vertically by at least half the shorter one?
    private static func shareARow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.5
    }

    /// A row read as one line of text.
    private static func line(_ row: Row) -> Fragment {
        Fragment(text: row.map(\.text).joined(separator: " "), frame: frame(of: row))
    }

    /// The horizontal range each column may take its width from: up to the next column.
    private static func columnBounds(_ columns: [[Fragment]], within bounds: Bounds) -> [Bounds] {
        columns.indices.map { index in
            let lower = index == 0 ? bounds.lowerBound : frame(of: columns[index - 1]).maxX
            let upper = index == columns.count - 1 ? bounds.upperBound : frame(of: columns[index + 1]).minX
            return lower...max(lower, upper)
        }
    }

    private static func frame(of fragments: [Fragment]) -> CGRect {
        fragments.dropFirst().reduce(fragments.first?.frame ?? .zero) { $0.union($1.frame) }
    }

    private static func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) > max(a.minX, b.minX)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        let sorted = values.filter { $0 > 0 }.sorted()
        return sorted.isEmpty ? nil : sorted[sorted.count / 2]
    }

    // MARK: - Words

    /// The marker opening a list item, trailing space included ("• ", "1. ", "a) "), if any.
    private static func listMarker(_ text: String) -> Substring? {
        // A letter only with a parenthesis: "A. Smith" opens a sentence, not a list.
        text.prefixMatch(of: #/^(?:[•◦▪▫‣⁃●○■□–—\-*·➤►✓✔☐☑]|\d{1,3}[.)]|[A-Za-z]\)|\(\d{1,3}\)|\([A-Za-z]\))\s+/#)?.output
    }

    /// A dash or an asterisk: markers that can also be punctuation.
    private static func isDash(_ marker: Substring) -> Bool {
        marker.first.map { "-–—*".contains($0) } == true
    }

    private static func endsWithHyphen(_ text: String) -> Bool {
        text.hasSuffix("-") && text.dropLast().last?.isLetter == true
    }

    /// Joins a wrapped line onto the text before it. A word hyphenated across the lines is
    /// rejoined ("au-" + "tomatiques"); the hyphen stays when it belongs to a compound: before
    /// a capital ("Claude-Based"), after a name ("Claude-" + "based") or in a word that
    /// already holds one ("state-of-the-" + "art").
    private static func joined(_ text: String, _ next: String) -> String {
        guard endsWithHyphen(text) else { return text + " " + next }
        let word = text.dropLast().split(separator: " ").last ?? ""
        let isCompound = next.first?.isLowercase != true || word.first?.isUppercase == true || word.contains("-")
        return isCompound ? text + next : text.dropLast() + next
    }

    /// The first letter, past any opening bracket or quote, is lower case.
    private static func startsInLowercase(_ text: String) -> Bool {
        text.first { $0.isLetter || $0.isNumber }?.isLowercase == true
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count
    }
}
