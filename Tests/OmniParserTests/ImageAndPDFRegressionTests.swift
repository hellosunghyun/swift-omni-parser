import CoreGraphics
import CoreText
import Foundation
import ImageIO
@testable import OmniParser
import UniformTypeIdentifiers
import Vision
import XCTest

final class ImageAndPDFRegressionTests: XCTestCase {
  func testAsyncVisionPreservesLegacySmallTextThreshold() {
    // 두 API의 SDK 기본값이 다르므로 기존 요청이 읽던 작은 글자를 계속 검사한다.
    XCTAssertEqual(DocumentOCR.makeRequest().minimumTextHeightFraction,
                   VNRecognizeTextRequest().minimumTextHeight)
  }

  func testCancellationDuringVisionRequestDiscardsSession() async throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: 2048, height: 4096,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2048, height: 4096))
    for line in 0..<60 {
      let text = NSAttributedString(string: "연구 자료 취소 검증 Research cancellation 2026 \(line)",
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String):
          CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 30, nil)])
      context.textPosition = CGPoint(x: 60, y: 4000 - line * 64)
      CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    let image = try XCTUnwrap(context.makeImage())
    let pool = DocumentOCRSessionPool()
    let progress = TestProgress()
    let task = Task {
      progress.append(.init(inputIndex: 0, phase: .recognizingText, fractionCompleted: 0))
      defer { progress.append(.init(inputIndex: 0, phase: .completed, fractionCompleted: 1)) }
      return try await pool.perform(image: image, orientation: .up) { _ in [] }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while progress.values.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
    try await Task.sleep(for: .milliseconds(30))
    // 너무 빠른 환경에서 이미 끝난 요청을 진행 중 취소 성공으로 세지 않는다.
    guard progress.values.last?.phase == .recognizingText else {
      _ = try await task.value
      throw XCTSkip("Vision 요청이 취소 시점 전에 끝나 진행 중 취소를 검증하지 못했습니다.")
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("진행 중 Vision 요청의 취소를 무시했습니다.")
    } catch is CancellationError { }
    XCTAssertEqual(pool.cachedSessionCount, 0)
  }

  func testDifficultGeneratedKoreanScans() async throws {
    for name in ["skew-seven-degrees", "low-resolution", "complex-table"] {
      let sample = try GeneratedOCRScan.make(name)
      let result = try await DocumentParser.parse(.data(sample.data, fileName: name + ".pdf"),
        options: .init(extractImages: true, performOCR: true))
      XCTAssertTrue(GeneratedOCRScan.normalized(result.fullText)
        .contains(GeneratedOCRScan.normalized(sample.marker)))
      XCTAssertTrue(result.fullText.contains("연구") || result.fullText.contains("한영"))
      // 표는 OCR 문자만 읽는다. 셀 복원이나 모든 문서의 같은 정확도를 보장하지 않는다.
      let errorRate = GeneratedOCRScan.characterErrorRate(sample.expected, result.fullText)
      XCTAssertLessThanOrEqual(errorRate, name == "complex-table" ? 0.15 : 0.08, name)
      XCTAssertEqual(result.images.count, 1)
      XCTAssertTrue(result.blocks.allSatisfy { $0.kind != .tableCell })
      XCTAssertFalse(result.warnings.contains {
        $0.code == .imageOCRFailed || $0.code == .extractionFailed
      })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testRepeatedPDFImagePlacementsHaveUniqueIdentifiers() async throws {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: 600, height: 300)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    let image = try markerImage()
    context.beginPDFPage(nil)
    context.draw(image, in: CGRect(x: 10, y: 50, width: 260, height: 100))
    context.draw(image, in: CGRect(x: 320, y: 50, width: 260, height: 100))
    context.endPDFPage()
    context.closePDF()
    let result = try await DocumentParser.parse(.data(bytes as Data, fileName: "repeated.pdf"),
      options: .init(extractImages: true))
    XCTAssertEqual(result.images.count, 2)
    XCTAssertEqual(Set(result.images.map(\.id)).count, 2)
    XCTAssertNotEqual(result.images.first?.location.bounds, result.images.last?.location.bounds)
    TestFixtures.assertTextConsistency(result)
  }

  func testDirectImageInputAndTIFFFrameOrientation() async throws {
    let image = try markerImage()
    let direct = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(extractImages: true))
    XCTAssertEqual(direct.format, .image)
    XCTAssertEqual(direct.images.count, 1)
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
      bytes, UTType.tiff.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(destination, image,
      [kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue] as CFDictionary)
    CGImageDestinationAddImage(destination, image,
      [kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let result = try await DocumentParser.parse(.data(bytes as Data, fileName: "frames.tiff"),
      options: .init(extractImages: true))
    XCTAssertEqual(result.images.map(\.location.page), [1, 2])
    XCTAssertEqual(result.images.map(\.orientation), [.up, .right])
    TestFixtures.assertTextConsistency(result)
  }

  func testNativeScannedAndMixedPDF() async throws {
    for pages in [[false], [true], [false, true]] {
      let result = try await DocumentParser.parse(.data(try pdf(pages), fileName: "pages.pdf"),
        options: .init(extractImages: true, performOCR: true))
      if pages.contains(false) { XCTAssertTrue(result.fullText.contains("NATIVE PAGE MARKER")) }
      if pages.contains(true) {
        XCTAssertTrue(result.blocks.contains {
          $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
        })
      }
      if pages.count == 2 {
        XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR && $0.location.page == 2 })
      }
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testConstrainedPDFBatchPreservesSingleDocumentResults() async throws {
    let documents: [DocumentInput] = try [[false, false], [true, true], [false, true, true]].map {
      .data(try pdf($0), fileName: "pages.pdf")
    }
    let options = DocumentParserOptions(extractImages: true, performOCR: true,
      maximumConcurrentDocuments: 2, maximumConcurrentPDFPages: 2)
    var expected: [DocumentParseResult] = []
    for input in documents {
      expected.append(try await DocumentParser.parse(input, options: options))
    }
    XCTAssertFalse(expected[0].fullText.isEmpty)
    XCTAssertEqual(expected[1].images.count, 2)
    XCTAssertEqual(expected[2].images.count, 2)

    var inputs = documents
    inputs.insert(.data(Data([0, 1, 2]), fileName: "broken.pdf"), at: 1)
    var constrained = options
    // 작업 예산보다 큰 페이지도 한 장씩 처리하며 결과를 바꾸지 않는지 확인한다.
    constrained.pdfWorkingMemoryTargetBytes = 1
    let results = try await DocumentParser.parseBatch(inputs, options: constrained)
    XCTAssertEqual(results.count, inputs.count)
    for (index, outcome) in results.enumerated() {
      if index == 1 {
        guard case .failure(let error) = outcome else {
          return XCTFail("손상 입력의 개별 실패가 보존되지 않았습니다.")
        }
        XCTAssertEqual(error, .unsupportedFormat)
      } else {
        guard case .success(let result) = outcome else {
          return XCTFail("정상 PDF 결과가 보존되지 않았습니다.")
        }
        try assertPDFResult(result, matches: expected[index < 1 ? index : index - 1])
      }
    }
  }

  private func assertPDFResult(_ result: DocumentParseResult,
                               matches expected: DocumentParseResult) throws {
    XCTAssertEqual(result.format, expected.format)
    XCTAssertTrue(result.fullText == expected.fullText)
    XCTAssertEqual(result.blocks, expected.blocks)
    XCTAssertEqual(result.warnings, expected.warnings)
    XCTAssertEqual(result.images.count, expected.images.count)
    for (image, reference) in zip(result.images, expected.images) {
      XCTAssertEqual(image.id, reference.id)
      XCTAssertEqual(image.location, reference.location)
      XCTAssertEqual(image.orientation, reference.orientation)
      XCTAssertEqual(image.sourceDescription, reference.sourceDescription)
      // PNG 컨테이너 바이트 대신 생성한 8비트 그림의 크기·sRGB 픽셀을 대조한다.
      XCTAssertEqual(try rasterFingerprint(image.pngData),
                     try rasterFingerprint(reference.pngData))
    }
    TestFixtures.assertTextConsistency(result)
  }

  private func rasterFingerprint(_ data: Data) throws -> String {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    var pixels = Data(count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { storage in
      let context = try XCTUnwrap(CGContext(data: storage.baseAddress,
        width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue))
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    var fingerprint = Data("\(image.width)x\(image.height):".utf8)
    fingerprint.append(pixels)
    return TestFixtures.hash(fingerprint)
  }

  private func markerImage() throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(
      TestFixtures.url("LegacyImage.png") as CFURL, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  /// 같은 자체 그림으로 일반·스캔·혼합 문서를 생성해 외부 PDF 자산에 의존하지 않는다.
  private func pdf(_ scannedPages: [Bool]) throws -> Data {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: 600, height: 300)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    for scanned in scannedPages {
      context.beginPDFPage(nil)
      if scanned {
        context.draw(try markerImage(), in: CGRect(x: 0, y: 50, width: 600, height: 120))
      } else {
        let text = NSAttributedString(string: "NATIVE PAGE MARKER", attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String):
            CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        ])
        context.textPosition = CGPoint(x: 20, y: 200)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
      }
      context.endPDFPage()
    }
    context.closePDF()
    return bytes as Data
  }
}

/// 외부 자산 없이 동일한 글꼴·문구로 기울기, 해상도, 표의 영향을 재현한다.
private enum GeneratedOCRScan {
  struct Sample {
    let data: Data
    let expected: String
    let marker: String
  }

  static func make(_ name: String) throws -> Sample {
    let low = name == "low-resolution"
    let width = low ? 595 : 1654, height = low ? 842 : 2339
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let scale = CGFloat(width) / 1654
    context.scaleBy(x: scale, y: scale)
    if name == "skew-seven-degrees" {
      context.translateBy(x: 827, y: 1169.5)
      context.rotate(by: 7 * .pi / 180)
      context.translateBy(x: -827, y: -1169.5)
    }
    let table = name == "complex-table"
    let marker = table ? "TABLE CHECK 2026" : low ? "LOW RESOLUTION 2026" : "SKEW CHECK 2026"
    var canvas = Canvas(context: context)
    canvas.draw(marker, x: 180, y: 2050, size: 52)
    canvas.draw("한영 문서 분석 결과를 확인합니다. Research Report", x: 180, y: 1940)
    if table { canvas.table() } else { canvas.body() }
    return Sample(data: try pdf(XCTUnwrap(context.makeImage())),
                  expected: canvas.lines.joined(separator: "\n"), marker: marker)
  }

  private struct Canvas {
    let context: CGContext
    var lines: [String] = []

    mutating func draw(_ text: String, x horizontal: CGFloat, y vertical: CGFloat,
                       size: CGFloat = 40) {
      lines.append(text)
      let value = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String):
          CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
          CGColor(gray: 0, alpha: 1)
      ])
      context.textPosition = CGPoint(x: horizontal, y: vertical)
      CTLineDraw(CTLineCreateWithAttributedString(value), context)
    }

    mutating func body() {
      for row in 1...12 {
        draw(String(format: "LINE%02d", row) + " 연구 자료와 측정값을 검토합니다. Document Study 42.",
             x: 180, y: CGFloat(1780 - row * 105), size: 36)
      }
    }

    mutating func table() {
      let columns: [CGFloat] = [130, 520, 830, 1190, 1530]
      context.setLineWidth(2)
      context.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
      for row in 0...9 {
        let vertical = CGFloat(1800 - row * 130)
        context.move(to: CGPoint(x: columns[0], y: vertical))
        context.addLine(to: CGPoint(x: columns[4], y: vertical))
      }
      for horizontal in columns {
        context.move(to: CGPoint(x: horizontal, y: 1800))
        context.addLine(to: CGPoint(x: horizontal, y: 630))
      }
      context.strokePath()
      for (columnIndex, text) in ["항목 Item", "수량 Qty", "금액 Amount", "상태 Status"].enumerated() {
        draw(text, x: columns[columnIndex] + 15, y: 1710, size: 35)
      }
      for row in 1...8 {
        let values = [String(format: "ROW%02d 연구", row), "\(row * 3)",
                      "$\(row * 123).45", "완료 PASS"]
        for (columnIndex, text) in values.enumerated() {
          draw(text, x: columns[columnIndex] + 15, y: CGFloat(1710 - row * 130), size: 35)
        }
      }
    }
  }

  private static func pdf(_ image: CGImage) throws -> Data {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let pdf = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.draw(image, in: box)
    pdf.endPDFPage()
    pdf.closePDF()
    return bytes as Data
  }

  static func normalized(_ value: String) -> String { value.filter { !$0.isWhitespace } }

  /// 한글 완성 문자도 한 글자로 세며 공백만 제외한다. 읽기 순서 오류도 오차에 포함된다.
  static func characterErrorRate(_ expected: String, _ actual: String) -> Double {
    let source = [Character](normalized(expected)), target = [Character](normalized(actual))
    var previous = Array(0...target.count)
    for (rowIndex, left) in source.enumerated() {
      var current = [rowIndex + 1]
      for (columnIndex, right) in target.enumerated() {
        current.append(min(current[columnIndex] + 1, previous[columnIndex + 1] + 1,
                           previous[columnIndex] + (left == right ? 0 : 1)))
      }
      previous = current
    }
    return Double(previous.last ?? 0) / Double(max(1, source.count))
  }
}
