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
