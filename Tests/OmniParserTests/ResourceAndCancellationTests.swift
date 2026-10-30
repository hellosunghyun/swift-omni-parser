import Foundation
@testable import OmniParser
import XCTest

final class ResourceAndCancellationTests: XCTestCase {
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

  func testRTFMalformedWarningsAreBounded() throws {
    let bytes = Data(("{\\rtf1 kept}" + String(repeating: "}", count: 100_000)).utf8)
    let result = try DocumentRTFPictureReader.read(bytes, options: .init())
    XCTAssertEqual(result.warnings.filter { $0.code == .malformedContent }.count, 1)
    XCTAssertNotNil(result.warnings.first?.location)
  }

  func testRTFControlWordScanRespondsToCancellation() async throws {
    // 각 제어어가 4096 경계를 건너뛰어도 진행 바이트 수로 취소를 확인해야 한다.
    let bytes = Data(("{\\rtf1 " + String(repeating: "\\abcdef ", count: 2_000_000) + "}").utf8)
    let task = Task.detached {
      _ = try DocumentRTFPictureReader.read(bytes, options: .init())
    }
    try await Task.sleep(nanoseconds: 5_000_000)
    task.cancel()
    do {
      try await task.value
      XCTFail("긴 RTF 스캔 도중 취소를 무시했습니다.")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testOversizedRTFControlTokensAreRejected() throws {
    for source in ["{\\rtf1 \\" + String(repeating: "a", count: 65) + "}",
                   "{\\rtf1\\fs" + String(repeating: "9", count: 100) + " kept}"] {
      XCTAssertThrowsError(
        try DocumentRTFPictureReader.read(Data(source.utf8), options: .init())
      ) {
        XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
      }
    }
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
