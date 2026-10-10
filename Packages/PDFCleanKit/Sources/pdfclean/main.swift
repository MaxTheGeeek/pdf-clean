// pdfclean: developer CLI for the PDFCleanKit pipeline (FR-24, task T-040). macOS only.
import Foundation
import PDFCleanKit

let message = "pdfclean \(PDFCleanKit.version): not implemented yet (task T-040 in specs/06-tasks.md)\n"
FileHandle.standardError.write(Data(message.utf8))
exit(1)
