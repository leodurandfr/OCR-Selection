import CoreGraphics
import Testing
@testable import OCRSelection

/// Layouts are built by hand on a simple grid: every character is 10 px wide, a line is
/// 20 px tall and lines of a paragraph are 28 px apart, so the widths below read as
/// character counts. Each fragment is what Vision's text recognition reports: a run of
/// text on one visual line, a table cell or a line of one column.
struct TextAssemblerTests {
    // MARK: Paragraphs

    @Test func joinsWrappedParagraph() {
        let layout = layout(
            line("The quick brown fox jumps over the lazy", row: 0),
            line("dog and keeps running across the field", row: 1),
            line("until dusk.", row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "The quick brown fox jumps over the lazy dog and keeps running across the field until dusk.")
    }

    @Test func keepsLineBreaksWhereTheNextWordWouldHaveFitted() {
        let layout = layout(
            line("A much wider line of text that sets the column width", row: 0),
            line("Roses are red,", row: 2),
            line("Violets are blue,", row: 3),
            line("Sugar is sweet,", row: 4),
            line("And so are you.", row: 5)
        )
        #expect(TextAssembler.text(from: layout) ==
            "A much wider line of text that sets the column width\n\nRoses are red,\nViolets are blue,\nSugar is sweet,\nAnd so are you.")
    }

    @Test func rejoinsWordHyphenatedAcrossLines() {
        let layout = layout(
            line("Les retours à la ligne au-", row: 0),
            line("tomatiques deviennent des", row: 1),
            line("sauts.", row: 2),
            line("Signé", row: 3)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Les retours à la ligne automatiques deviennent des sauts.\nSigné")
    }

    @Test func neverBreaksAfterAHyphenatedLine() {
        // The wide line makes "ligne au-" look short, but a hyphen at the end means it wrapped.
        let layout = layout(
            line("A much wider line of text that sets the column width", row: 0),
            line("Les retours à la ligne au-", row: 2),
            line("tomatiques.", row: 3)
        )
        #expect(TextAssembler.text(from: layout) ==
            "A much wider line of text that sets the column width\n\nLes retours à la ligne automatiques.")
    }

    @Test func keepsTheHyphenOfACompoundBrokenAtTheLineEnd() {
        let layout = layout(
            line("A home assistant that runs as a Claude-", row: 0),
            line("based service on a state-of-the-", row: 1),
            line("art board.", row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "A home assistant that runs as a Claude-based service on a state-of-the-art board.")
    }

    @Test func joinsALineThatWrappedJustBeforeADash() {
        let layout = layout(
            line("Open from 9 to 5 every day of the", row: 0),
            line("- weekends included - and closed on", row: 1),
            line("public holidays.", row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Open from 9 to 5 every day of the - weekends included - and closed on public holidays.")
    }

    @Test func joinsSentenceEndingAtFullWidth() {
        let layout = layout(
            line("It was a bright cold day, the clocks struck.", row: 0),
            line("Winston Smith slipped quickly through the", row: 1),
            line("glass doors.", row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "It was a bright cold day, the clocks struck. Winston Smith slipped quickly through the glass doors.")
    }

    @Test func joinsDoubleSpacedLines() {
        let layout = layout(
            line("The quick brown fox jumps over the lazy", y: 0),
            line("dog and keeps running.", y: 40)
        )
        #expect(TextAssembler.text(from: layout) == "The quick brown fox jumps over the lazy dog and keeps running.")
    }

    @Test func keepsShortSingleLinesApart() {
        let lines = ["Name: Jane Appleseed", "Email: jane@example.com", "Phone: +33 6 12 34 56 78"]
        let layout = RecognizedLayout(fragments: lines.enumerated().map { line($1, row: $0) })
        #expect(TextAssembler.text(from: layout) == lines.joined(separator: "\n"))
    }

    @Test func keepsALongLineThatSetsTheWidthItselfApart() {
        // Nothing else is as wide as the first line, so it proves nothing about wrapping.
        let layout = layout(line("Address: 12 rue de la Paix", row: 0), line("City: Paris 75002", row: 1))
        #expect(TextAssembler.text(from: layout) == "Address: 12 rue de la Paix\nCity: Paris 75002")
    }

    @Test func aLineReadAsTwoFragmentsDoesNotConfirmItsOwnWidth() {
        let layout = layout(
            line("Address: 12 rue de la", row: 0), line("Paix", x: 220, row: 0),
            line("City: Paris 75002", row: 1)
        )
        #expect(TextAssembler.text(from: layout) == "Address: 12 rue de la Paix\nCity: Paris 75002")
    }

    @Test func blankLineBetweenSpacedParagraphs() {
        let layout = layout(line("First paragraph.", row: 0), line("Second paragraph.", row: 2))
        #expect(TextAssembler.text(from: layout) == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func indentedLineStartsANewParagraph() {
        let layout = layout(
            line("This first paragraph wraps onto a", row: 0),
            line("second line.", row: 1),
            line("Indented second paragraph starts", x: 40, row: 2),
            line("here.", row: 3)
        )
        #expect(TextAssembler.text(from: layout) ==
            "This first paragraph wraps onto a second line.\nIndented second paragraph starts here.")
    }

    @Test func headingInLargerTypeStaysOnItsOwnLine() {
        // Wide enough that the next word would not fit after it: only its size sets it apart.
        let layout = RecognizedLayout(fragments: [
            .init(text: "Release notes for the version", frame: CGRect(x: 0, y: 0, width: 400, height: 36)),
            line("The update adds a dark mode and makes", y: 44),
            line("exports faster.", y: 72),
        ])
        #expect(TextAssembler.text(from: layout) ==
            "Release notes for the version\nThe update adds a dark mode and makes exports faster.")
    }

    @Test func joinsLinesWhoseBoxesDifferInHeight() {
        // Same font: descenders and accents alone make the first box taller.
        let layout = RecognizedLayout(fragments: [
            .init(text: "cuivre, conçu les boîtiers (BOM), Diode n'a", frame: CGRect(x: 0, y: 0, width: 430, height: 28)),
            line("presque rien guidé du tout.", y: 30),
        ])
        #expect(TextAssembler.text(from: layout) == "cuivre, conçu les boîtiers (BOM), Diode n'a presque rien guidé du tout.")
    }

    // MARK: Lists

    @Test func listsOneItemPerLineWithNesting() {
        let layout = layout(
            line("Bring:", row: 0),
            line("• An Apple ID with two-factor authentication", x: 20, row: 2),
            line("• enrolled in the developer program", x: 60, row: 3),
            line("• Coffee.", x: 20, row: 4)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Bring:\n\n• An Apple ID with two-factor authentication\n\t• enrolled in the developer program\n• Coffee.")
    }

    @Test func joinsListItemWrappedUnderItsText() {
        let layout = layout(
            line("• Run the install command and wait for the", x: 20, row: 0),
            line("progress bar to finish.", x: 40, row: 1),
            line("• Restart.", x: 20, row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "• Run the install command and wait for the progress bar to finish.\n• Restart.")
    }

    @Test func numberedItemsStayOnePerLine() {
        let layout = layout(
            line("1. Open the lid of the machine and fill the", row: 0),
            line("2. Press the button.", row: 1)
        )
        #expect(TextAssembler.text(from: layout) ==
            "1. Open the lid of the machine and fill the\n2. Press the button.")
    }

    // MARK: Tables and columns

    @Test func tableRowsAreTabSeparatedWhateverTheFragmentOrder() {
        // Vision reports a table column by column.
        let layout = layout(
            line("Region", row: 0), line("North America", row: 1), line("Europe", row: 2),
            line("Q1", x: 200, row: 0), line("1,204", x: 200, row: 1), line("987", x: 200, row: 2),
            line("Q2", x: 300, row: 0), line("1,388", x: 300, row: 1), line("1,020", x: 300, row: 2)
        )
        #expect(TextAssembler.text(from: layout) == "Region\tQ1\tQ2\nNorth America\t1,204\t1,388\nEurope\t987\t1,020")
    }

    @Test func tableCellWrappedOntoTwoLinesStaysOneCell() {
        let layout = layout(
            line("Kerning", row: 0), line("Space between two letters, adjusted", x: 150, row: 0),
            line("pair by pair.", x: 150, row: 1),
            line("Leading", row: 2), line("Space between lines", x: 150, row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Kerning\tSpace between two letters, adjusted pair by pair.\nLeading\tSpace between lines")
    }

    @Test func tableWhoseCellsAllWrapStaysATable() {
        // Half the visual lines hold a single column: the wrapped halves of the definitions.
        let layout = layout(
            line("Kerning", row: 0), line("Space between two letters, adjusted", x: 150, row: 0),
            line("pair by pair.", x: 150, row: 1),
            line("Leading", row: 2), line("Space between two lines of a text,", x: 150, row: 2),
            line("from baseline to baseline.", x: 150, row: 3),
            line("Tracking", row: 4), line("Space added evenly across a whole", x: 150, row: 4),
            line("word or line.", x: 150, row: 5)
        )
        #expect(TextAssembler.text(from: layout) == [
            "Kerning\tSpace between two letters, adjusted pair by pair.",
            "Leading\tSpace between two lines of a text, from baseline to baseline.",
            "Tracking\tSpace added evenly across a whole word or line.",
        ].joined(separator: "\n"))
    }

    @Test func tableBetweenTwoParagraphs() {
        let layout = layout(
            line("Our plans changed this year, and the", row: 0),
            line("prices are now:", row: 1),
            line("Plan", row: 2), line("Price", x: 200, row: 2),
            line("Pro", row: 3), line("$9.99", x: 200, row: 3),
            line("Taxes are included.", row: 4)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Our plans changed this year, and the prices are now:\nPlan\tPrice\nPro\t$9.99\nTaxes are included.")
    }

    @Test func readsSideBySideProseColumnsOneAfterTheOther() {
        let layout = layout(
            line("The first column wraps onto", row: 0), line("The second column also", x: 300, row: 0),
            line("a second line.", row: 1), line("wraps here.", x: 300, row: 1)
        )
        #expect(TextAssembler.text(from: layout) ==
            "The first column wraps onto a second line.\nThe second column also wraps here.")
    }

    @Test func readsMainTextBesideASidebarOneAfterTheOther() {
        // Only the main text runs on; the sidebar's short lines sit beside it.
        let layout = layout(
            line("The main text of the page runs on and", row: 0), line("Related", x: 450, row: 0),
            line("wraps onto a second line, then onto", row: 1), line("1.2 M views", x: 450, row: 1),
            line("a third line of the article.", row: 2), line("3 days ago", x: 450, row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "The main text of the page runs on and wraps onto a second line, then onto a third line of the article.\nRelated\n1.2 M views\n3 days ago")
    }

    @Test func readsColumnsWhoseLinesDoNotLineUpOneAfterTheOther() {
        // A video page: short lines under the player, cards in the sidebar, at their own pitch.
        let layout = layout(
            line("Claude designs a hub", y: 0), line("Treasure of Rome", x: 450, y: 14),
            line("753 k subscribers", y: 28), line("Micode", x: 450, y: 42),
            line("Anthropic works with Diode.", y: 56), line("1.1 M views", x: 450, y: 70),
            line("Restored Casino Roulette", x: 450, y: 98), line("5.5 M views", x: 450, y: 126)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Claude designs a hub\n753 k subscribers\nAnthropic works with Diode.\nTreasure of Rome\nMicode\n1.1 M views\nRestored Casino Roulette\n5.5 M views")
    }

    @Test func columnStartingALineHigherKeepsItsFirstLine() {
        let layout = layout(
            line("The left column starts one line", row: 0),
            line("higher than the right one and", row: 1), line("The right column also", x: 350, row: 1),
            line("wraps again.", row: 2), line("wraps here.", x: 350, row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "The left column starts one line higher than the right one and wraps again.\nThe right column also wraps here.")
    }

    @Test func eachColumnKeepsItsOwnLineSpacing() {
        // The left column is spaced one and a half, the right one single: interleaved, their
        // rows leave no gap, but the left column's lines are not paragraphs.
        let layout = layout(
            line("The left column is set with", y: 0), line("The right column is set", x: 350, y: 0),
            line("solid, with its lines all", x: 350, y: 24),
            line("generous spacing between", y: 40), line("close together in one", x: 350, y: 48),
            line("paragraph.", x: 350, y: 72),
            line("its lines.", y: 80)
        )
        #expect(TextAssembler.text(from: layout) ==
            "The left column is set with generous spacing between its lines.\nThe right column is set solid, with its lines all close together in one paragraph.")
    }

    @Test func columnsUnderAFullWidthTitle() {
        let layout = layout(
            line("Two columns of text under a title that spans both", row: 0),
            line("The first column wraps onto", row: 1), line("The second column also", x: 300, row: 1),
            line("a second line.", row: 2), line("wraps here.", x: 300, row: 2)
        )
        #expect(TextAssembler.text(from: layout) ==
            "Two columns of text under a title that spans both\nThe first column wraps onto a second line.\nThe second column also wraps here.")
    }

    // MARK: Settings and edge cases

    @Test func preserveLineBreaksKeepsEveryVisualLine() {
        let layout = layout(
            line("The quick brown fox jumps over the lazy", row: 0),
            line("• Run the install command and wait for the", x: 20, row: 1),
            line("progress bar.", x: 36, row: 2)
        )
        #expect(TextAssembler.text(from: layout, preserveLineBreaks: true) ==
            "The quick brown fox jumps over the lazy\n• Run the install command and wait for the\nprogress bar.")
    }

    @Test func emptyLayoutGivesEmptyText() {
        #expect(TextAssembler.text(from: RecognizedLayout(fragments: [])) == "")
    }
}

// MARK: - Fixtures

private let characterWidth: CGFloat = 10
private let lineHeight: CGFloat = 20
private let linePitch: CGFloat = 28

private func line(_ text: String, x: CGFloat = 0, row: Int) -> RecognizedLayout.Fragment {
    line(text, x: x, y: CGFloat(row) * linePitch)
}

private func line(_ text: String, x: CGFloat = 0, y: CGFloat) -> RecognizedLayout.Fragment {
    RecognizedLayout.Fragment(
        text: text,
        frame: CGRect(x: x, y: y, width: CGFloat(text.count) * characterWidth, height: lineHeight)
    )
}

private func layout(_ fragments: RecognizedLayout.Fragment...) -> RecognizedLayout {
    RecognizedLayout(fragments: fragments)
}
