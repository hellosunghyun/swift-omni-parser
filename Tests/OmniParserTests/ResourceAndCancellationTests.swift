import Foundation
@testable import OmniParser
import XCTest

final class ResourceAndCancellationTests: XCTestCase {
  func testSkippedRemoteHTMLImageKeepsBodyAndLocatedWarnings() async throws {
    let html = "<html><body><p>Kept</p><img src='https://example.invalid/image.png'></body></html>"
    let result = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "remote.html"),
      options: .init(performOCR: true))
    XCTAssertEqual(result.fullText, "Kept")
    XCTAssertTrue(result.images.isEmpty)
    XCTAssertTrue(result.warnings.contains { $0.code == .externalImageSkipped })
    XCTAssertTrue(result.warnings.allSatisfy { $0.location != nil })
    TestFixtures.assertTextConsistency(result)
  }

  func testConcurrentOCRPreservesResultsAtUserInitiatedPriority() async throws {
    let input = TestFixtures.input("LegacyImage.png")
    let task = Task(priority: .userInitiated) {
      try await DocumentParser.parseBatch([input, input, input],
        options: .init(performOCR: true, maximumConcurrentDocuments: 2))
    }
    let results = try await task.value
    XCTAssertEqual(results.count, 3)
    var texts: [String] = []
    for outcome in results {
      guard case .success(let result) = outcome else { return XCTFail("병렬 OCR이 실패했습니다.") }
      XCTAssertTrue(result.fullText.contains("IMAGE OCR MARKER"))
      XCTAssertTrue(result.images.isEmpty)
      TestFixtures.assertTextConsistency(result)
      texts.append(result.fullText)
    }
    XCTAssertEqual(Set(texts).count, 1)
  }

  func testArchiveTraversalIsRejected() async {
    do {
      _ = try await DocumentParser.parse(TestFixtures.input("Generated/Traversal.docx"))
      XCTFail("경로 탈출 항목을 허용했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .malformedDocument) }
  }

  func testActualInflationIsLimitedDespiteFalseDeclaredSize() throws {
    let bytes = try Data(contentsOf: TestFixtures.url("Generated/LyingSize.docx"))
    XCTAssertThrowsError(try DocumentArchiveReader.xmlEntries(bytes, options: .init())) {
      XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
    }
  }

  func testInputLimitRejectsBeforeExtraction() async {
    do {
      _ = try await DocumentParser.parse(.data(Data("too large".utf8), fileName: "note.txt"),
        options: .init(maximumInputBytes: 1))
      XCTFail("입력 한도를 적용하지 않았습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge) }
  }

  func testStructuredTextRecoveryIsReported() async throws {
    for (name, text) in [("broken.json", "{\"value\":"),
                         ("broken.xml", "<root><value>kept</root>"),
                         ("broken.rtf", "{\\rtf1 kept")] {
      let result = try await DocumentParser.parse(.data(Data(text.utf8), fileName: name))
      XCTAssertFalse(result.fullText.isEmpty)
      XCTAssertTrue(result.warnings.contains {
        $0.code == .malformedContent && $0.location != nil
      })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testSharedImagePathPreservesPNGWhenOCRFails() throws {
    let data = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let decoded = try DocumentImageDecoder.decode(data, maximumPixels: 40_000_000)
    let result = try DocumentRasterParser.parseImage(
      decoded.image, orientation: decoded.orientation, format: .image,
      location: .init(part: "test-image"), options: .init(extractImages: true, performOCR: true)
    ) { _, _, _ in throw DocumentParsingError.malformedDocument }
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.warnings.contains { $0.code == .imageOCRFailed })
    XCTAssertEqual(result.images.first?.location.part, "test-image")
  }

  func testXMLEntitiesAreNotExpanded() async throws {
    let source = "<!DOCTYPE root [<!ENTITY a 'ab'><!ENTITY b '&a;&a;'>]>"
      + "<root>&b;</root>"
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "entity.xml"))
    XCTAssertFalse(result.fullText.contains("abab"))
    XCTAssertTrue(result.warnings.contains { $0.code == .unsupportedElement })
  }

  func testPartialImageFailureKeepsBodyAndTable() async throws {
    let result = try await DocumentParser.parse(TestFixtures.input("LegacySample.doc"),
      options: .init(extractImages: true, maximumImagePixels: 1))
    XCTAssertTrue(result.fullText.contains("Legacy body marker"))
    XCTAssertTrue(result.blocks.contains { $0.kind == .tableCell })
    XCTAssertTrue(result.images.isEmpty)
    XCTAssertTrue(result.warnings.contains { $0.location != nil })
    TestFixtures.assertTextConsistency(result)
  }

  func testCancellationAtExtractionReportsCancelled() async {
    let progress = TestProgress()
    let task = Task {
      try await DocumentParser.parse(.data(Data("cancel".utf8), fileName: "note.txt")) { event in
        progress.append(event)
        if event.phase == .extracting { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    do {
      _ = try await task.value
      XCTFail("추출 도중 취소를 무시했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    XCTAssertEqual(progress.values.last?.phase, .cancelled)
    XCTAssertFalse(progress.values.contains { $0.phase == .completed })
  }

  func testOfficeTemporaryDirectoriesAreReleased() async throws {
    let before = try directories()
    _ = try await DocumentParser.parse(
      TestFixtures.input("RealWorld/xlsx/real-xlsx-01-DataTableCities.xlsx"))
    do {
      _ = try await DocumentParser.parse(TestFixtures.malformedWorkbook())
      XCTFail("잘못된 BIFF 버전을 허용했습니다.")
    } catch {
      XCTAssertEqual(error as? DocumentParsingError, .malformedDocument)
    }
    XCTAssertEqual(try directories(), before)
  }

  private func directories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path).filter {
        $0.hasPrefix("DocumentParsing-")
      })
  }
}
