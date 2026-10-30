import Foundation
import OmniParser
import XCTest

final class RTFRegressionTests: XCTestCase {
  func testRTFTableAndEmbeddedImage() async throws {
    let bytes = try sample()
    let result = try await DocumentParser.parse(.data(bytes, fileName: "generated.rtf"),
      options: .init(extractImages: true, performOCR: true))
    XCTAssertTrue(result.fullText.contains("Paper marker"))
    XCTAssertTrue(result.blocks.contains {
      $0.kind == .tableCell && $0.text == "Name" && $0.location.row == 1
        && $0.location.column == 1
    })
    XCTAssertEqual(result.images.count, 1)
    XCTAssertEqual(result.blocks.filter { $0.kind == .table }.count, 1)
    XCTAssertTrue(result.blocks.contains {
      $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
    })
    TestFixtures.assertTextConsistency(result)
  }

  func testRTFImageOptionsAreIndependent() async throws {
    for images in [false, true] {
      for ocr in [false, true] {
        let result = try await DocumentParser.parse(.data(try sample(), fileName: "options.rtf"),
          options: .init(extractImages: images, performOCR: ocr))
        XCTAssertEqual(result.images.count, images ? 1 : 0)
        XCTAssertEqual(result.blocks.contains { $0.kind == .imageOCR }, ocr)
        XCTAssertEqual(result.blocks.filter { $0.kind == .tableCell }.count, 4)
        XCTAssertFalse(result.fullText.contains("OMNIRTF"))
        TestFixtures.assertTextConsistency(result)
      }
    }
  }

  func testBinaryPicturePreservesEscapedTextAndReadingOrder() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    var bytes = Data("{\\rtf1 Before \\{escaped\\} {\\pict\\pngblip\\bin\(png.count) ".utf8)
    bytes.append(png)
    bytes.append(Data("} After\\par}".utf8))
    let result = try await DocumentParser.parse(.data(bytes, fileName: "binary.rtf"),
      options: .init(extractImages: true, performOCR: true))
    XCTAssertTrue(result.blocks.first?.text.contains("Before {escaped}") == true)
    XCTAssertEqual(result.blocks.last?.text, "After")
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR })
    TestFixtures.assertTextConsistency(result)
  }

  func testMalformedPictureKeepsTextAndFollowingImage() async throws {
    let source = try XCTUnwrap(String(data: sample(), encoding: .utf8))
      .replacingOccurrences(of: "Paper marker", with: "Paper marker{\\pict\\pngblip 0Z}")
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "broken.rtf"),
      options: .init(extractImages: true))
    XCTAssertEqual(result.images.count, 1)
    XCTAssertEqual(result.blocks.filter { $0.kind == .tableCell }.count, 4)
    XCTAssertTrue(result.warnings.contains { $0.code == .extractionFailed && $0.location != nil })
    XCTAssertTrue(result.fullText.contains("End marker"))
  }

  func testPreferredPictureDoesNotDuplicateFallback() async throws {
    let hex = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
      .map { String(format: "%02x", $0) }.joined()
    let source = "{\\rtf1 {\\*\\shppict{\\pict\\pngblip \(hex)}}"
      + "{\\nonshppict{\\pict\\wmetafile8 00}}End}"
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "fallback.rtf"),
      options: .init(extractImages: true, maximumEmbeddedImages: 1))
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.warnings.isEmpty)
    XCTAssertEqual(result.fullText, "End")
  }

  func testMalformedPreferredPictureUsesValidFallbackWithinImageLimit() async throws {
    let source = "{\\rtf1 Body\\par{\\*\\shppict{\\pict\\pngblip 0Z}}"
      + "{\\nonshppict{\\pict\\pngblip \(try imageHex())}}End}"
    let bytes = Data(source.utf8)
    let preferred = try XCTUnwrap(bytes.range(of: Data("{\\*\\shppict".utf8)))
    let fallback = try XCTUnwrap(bytes.range(of: Data("{\\nonshppict".utf8)))
    let result = try await DocumentParser.parse(.data(bytes, fileName: "recover-fallback.rtf"),
      options: .init(extractImages: true, maximumEmbeddedImages: 1))
    let image = try XCTUnwrap(result.images.first)
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(image.location.part?.hasPrefix("rtf/byte[\(fallback.lowerBound)]") == true)
    XCTAssertTrue(result.warnings.contains {
      $0.location?.part?.hasPrefix("rtf/byte[\(preferred.lowerBound)]") == true
    })
    XCTAssertFalse(result.warnings.contains { $0.code == .resourceLimitReached })
    XCTAssertTrue(result.fullText.contains("Body"))
    XCTAssertTrue(result.fullText.contains("End"))
    TestFixtures.assertTextConsistency(result)
  }

  func testCellImageLocationsAndOCRSurviveRasterBudget() async throws {
    let source = "{\\rtf1\\ansi\\trowd\\cellx4000\\intbl Before "
      + "{\\pict\\pngblip \(try imageHex())} After\\cell\\row\\pard End\\par}"
    let bytes = Data(source.utf8)
    let picture = try XCTUnwrap(bytes.range(of: Data("{\\pict".utf8)))
    for budget in [500 * 1024 * 1024, 1] {
      let result = try await DocumentParser.parse(.data(bytes, fileName: "cell-picture.rtf"),
        options: .init(extractImages: true, performOCR: true, maximumExpandedBytes: budget))
      let ocr = try XCTUnwrap(result.blocks.first {
        $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
      })
      XCTAssertEqual(ocr.location.row, 1)
      XCTAssertEqual(ocr.location.column, 1)
      XCTAssertNotNil(ocr.location.paragraph)
      XCTAssertTrue(ocr.location.part?.hasPrefix("rtf/byte[\(picture.lowerBound)]") == true)
      XCTAssertEqual(result.images.count, budget == 1 ? 0 : 1)
      if let image = result.images.first {
        XCTAssertEqual(image.location.row, 1)
        XCTAssertEqual(image.location.column, 1)
        XCTAssertEqual(image.location.part, ocr.location.part)
      }
      XCTAssertTrue(result.warnings.contains {
        $0.code == .uncertainReadingOrder && $0.location?.row == 1 && $0.location?.column == 1
      })
      if budget == 1 {
        XCTAssertTrue(result.warnings.contains { $0.code == .resourceLimitReached })
      }
      XCTAssertTrue(result.fullText.contains("Before"))
      XCTAssertTrue(result.fullText.contains("After"))
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testSeparateTablesKeepParagraphsAndVerticalMergeLocations() async throws {
    let source = """
    {\\rtf1\\ansi
    \\trowd\\clvmgf\\cellx4000\\intbl First paragraph\\par
    \\intbl Second paragraph\\cell\\row
    \\trowd\\clvmrg\\cellx4000\\intbl\\cell\\row
    \\pard Between tables\\par
    \\trowd\\cellx4000\\intbl Other table\\cell\\row
    \\pard End\\par}
    """
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "tables.rtf"))
    let first = try XCTUnwrap(result.blocks.first {
      $0.kind == .tableCell && $0.text.contains("First paragraph")
    })
    let other = try XCTUnwrap(result.blocks.first {
      $0.kind == .tableCell && $0.text == "Other table"
    })
    let between = try XCTUnwrap(result.blocks.first { $0.text == "Between tables" })
    XCTAssertEqual(result.blocks.filter { $0.kind == .table }.count, 2)
    XCTAssertEqual(first.text, "First paragraph\nSecond paragraph")
    XCTAssertEqual(first.location.row, 1)
    XCTAssertEqual(first.location.column, 1)
    XCTAssertEqual(first.location.rowSpan, 2)
    XCTAssertEqual(other.location.row, 1)
    XCTAssertEqual(other.location.column, 1)
    XCTAssertNotEqual(first.location.part, other.location.part)
    XCTAssertLessThan(first.readingOrder, between.readingOrder)
    XCTAssertLessThan(between.readingOrder, other.readingOrder)
    TestFixtures.assertTextConsistency(result)
  }

  func testPictureReplacementKeepsControlWordBoundaries() async throws {
    let hex = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
      .map { String(format: "%02x", $0) }.joined()
    let bytes = Data("{\\rtf1\\pard{\\pict\\pngblip \(hex)}After}".utf8)
    for images in [false, true] {
      let result = try await DocumentParser.parse(.data(bytes, fileName: "boundaries.rtf"),
        options: .init(extractImages: images))
      XCTAssertEqual(result.fullText, "After")
      XCTAssertEqual(result.images.count, images ? 1 : 0)
    }
  }

  func testRTFImageAndBinaryLimits() async throws {
    let bytes = try sample()
    for options in [DocumentParserOptions(extractImages: true, maximumImagePixels: 1),
                    .init(extractImages: true, maximumExpandedBytes: 1)] {
      let result = try await DocumentParser.parse(.data(bytes, fileName: "limits.rtf"),
                                                options: options)
      XCTAssertTrue(result.images.isEmpty)
      XCTAssertTrue(result.warnings.contains { $0.code == .resourceLimitReached })
      XCTAssertTrue(result.fullText.contains("End marker"))
    }
    var many = Data(bytes.dropLast())
    many.append(Data("{\\pict\\pngblip 00}}".utf8))
    let limited = try await DocumentParser.parse(.data(many, fileName: "count.rtf"),
      options: .init(extractImages: true, maximumEmbeddedImages: 1))
    XCTAssertEqual(limited.images.count, 1)
    XCTAssertTrue(limited.warnings.contains { $0.code == .resourceLimitReached })
    do {
      _ = try await DocumentParser.parse(
        .data(Data("{\\rtf1 {\\pict\\bin2147483647 x}}".utf8), fileName: "risk.rtf"))
      XCTFail("손상된 binary 길이를 시스템 importer에 전달했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .malformedDocument) }
  }

  func testRTFUnicodeAndMergedCellLocations() async throws {
    let text = "한글 English"
    let escaped = text.utf16.map { "\\u\(Int16(bitPattern: $0))?" }.joined()
    let source = "{\\rtf1\\ansi\\uc1 \(escaped)\\par"
      + "\\trowd\\clmgf\\cellx2000\\clmrg\\cellx4000"
      + "\\intbl Merged\\cell\\cell\\row}"
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "merged.rtf"))
    XCTAssertTrue(result.fullText.contains(text))
    let cell = try XCTUnwrap(result.blocks.first { $0.kind == .tableCell && $0.text == "Merged" })
    XCTAssertEqual(cell.location.row, 1)
    XCTAssertEqual(cell.location.column, 1)
    XCTAssertEqual(cell.location.columnSpan, 2)
  }

  func testExistingRTFSamplesHaveTablesAndJPEGImages() async throws {
    let table = try await DocumentParser.parse(
      TestFixtures.input("RealWorld/rtf/real-rtf-02-testRTFJapanese.rtf"))
    XCTAssertTrue(table.blocks.contains { $0.kind == .tableCell })
    let images = try await DocumentParser.parse(
      TestFixtures.input("RealWorld/rtf/real-rtf-03-testRTFRegularImages.rtf"),
      options: .init(extractImages: true))
    XCTAssertEqual(images.images.count, 2)
    TestFixtures.assertTextConsistency(table)
    TestFixtures.assertTextConsistency(images)
  }

  private func imageHex() throws -> String {
    try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
      .map { String(format: "%02x", $0) }.joined()
  }

  private func sample() throws -> Data {
    let hex = try imageHex()
    return Data("""
    {\\rtf1\\ansi\\ansicpg1252
    Paper marker\\par
    \\trowd\\cellx2000\\cellx4000\\intbl Name\\cell Value\\cell\\row
    \\trowd\\cellx2000\\cellx4000\\intbl Sample\\cell 42\\cell\\row
    \\pard {\\pict\\pngblip \(hex)}\\par
    End marker\\par}
    """.utf8)
  }
}
