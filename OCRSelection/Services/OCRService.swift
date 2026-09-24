import CoreGraphics
import Foundation
import Vision

enum OCRError: Error {
    case noTextFound
    case visionFailed(Error)
}

@MainActor
struct OCRService: TextRecognizing {
    /// Document recognition rather than plain text recognition: besides the lines, it reports
    /// paragraphs, lists and tables, which is what lets `TextAssembler` undo the wrapping of
    /// the captured region instead of hard-coding a newline after every visual line.
    func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true

        let documents: [DocumentObservation]
        do {
            // Vision's `perform` is nonisolated: the recognition runs off the main actor.
            documents = try await request.perform(on: image)
        } catch {
            throw OCRError.visionFailed(error)
        }

        let text = await Self.assemble(
            documents,
            imageSize: CGSize(width: image.width, height: image.height),
            preserveLineBreaks: UserDefaults.standard.bool(forKey: AppSettings.preserveLineBreaksKey)
        )
        guard !text.isEmpty else { throw OCRError.noTextFound }
        return text
    }

    /// nonisolated so the geometry work on a large capture stays off the main actor.
    private nonisolated static func assemble(
        _ documents: [DocumentObservation], imageSize: CGSize, preserveLineBreaks: Bool
    ) async -> String {
        documents
            .map { TextAssembler.text(from: RecognizedLayout($0.document, imageSize: imageSize), preserveLineBreaks: preserveLineBreaks) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

extension RecognizedLayout {
    init(_ document: DocumentObservation.Container, imageSize: CGSize) {
        func frame(_ region: NormalizedRegion) -> CGRect {
            region.boundingBox.toImageCoordinates(imageSize, origin: .upperLeft)
        }
        func fragment(_ observation: RecognizedTextObservation) -> Fragment {
            Fragment(text: observation.transcript, frame: frame(observation.boundingRegion))
        }

        paragraphs = document.paragraphs.map {
            Paragraph(text: $0.transcript, lines: $0.lines.map(fragment), frame: frame($0.boundingRegion))
        }
        lists = document.lists.map { list in
            List(
                items: list.items.map { ListItem(marker: $0.markerString, text: $0.itemString, frame: frame($0.content.boundingRegion)) },
                frame: frame(list.boundingRegion)
            )
        }
        tables = document.tables.map { table in
            // A merged cell is listed once per row it spans.
            var seen = Set<[Int]>()
            let cells = table.rows.joined().filter {
                seen.insert([$0.rowRange.lowerBound, $0.rowRange.upperBound, $0.columnRange.lowerBound, $0.columnRange.upperBound]).inserted
            }
            return Table(
                rowCount: table.rows.count,
                columnCount: table.columns.count,
                cells: cells.map { cell in
                    Cell(
                        text: cell.content.text.transcript,
                        rows: cell.rowRange,
                        columns: cell.columnRange,
                        frame: frame(cell.content.boundingRegion),
                        words: (cell.content.text.words ?? []).map(fragment),
                        hasWrappedText: cell.content.text.lines.contains { $0.shouldWrapToNextLine == true }
                    )
                },
                frame: frame(table.boundingRegion)
            )
        }
    }
}
