import CoreGraphics
import CoreText
import Foundation
@testable import OmniParser
import Synchronization
import XCTest

/// 같은 원본 래스터/좌표를 유지한 채 OCR 경계 결과만 주입한다.
/// 다른 픽셀을 같은 영역으로 가장하는 테스트 더블은 사용하지 않는다.
final class PDFRegionRecognitionPolicyTests: XCTestCase {
  private final class Calls: Sendable {
    private let count = Mutex(0)
    func next() -> Int { count.withLock { $0 += 1; return $0 } }
    var value: Int { count.withLock { $0 } }
  }

  private enum RecognitionFailure: Error { case firstAttempt }

  func testRepeatedRegionRetriesAfterRecognitionFailure() async throws {
    let fixture = try fixture()
    let calls = Calls()
    let result = try await DocumentPDFPageParser.recognize(
      fixture.page
    ) { image, location, bounds in
      XCTAssertTrue(image === fixture.raster.image)
      if calls.next() == 1 { throw RecognitionFailure.firstAttempt }
      return [Self.recognized(location: location, bounds: bounds)]
    }
    XCTAssertEqual(calls.value, 2)
    assertPreservedResult(result, from: fixture.page, recognizedPart: "repeat/second")
    XCTAssertEqual(result.result.warnings.count, 1)
    XCTAssertTrue(result.result.warnings.first?.code == .imageOCRFailed)
    XCTAssertTrue(result.result.warnings.first?.location == fixture.page.imageJobs[0].location)
  }

  func testRepeatedRegionRetriesAfterEmptyRecognition() async throws {
    let fixture = try fixture()
    let calls = Calls()
    let result = try await DocumentPDFPageParser.recognize(
      fixture.page
    ) { image, location, bounds in
      XCTAssertTrue(image === fixture.raster.image)
      if calls.next() == 1 { return [] }
      return [Self.recognized(location: location, bounds: bounds)]
    }
    XCTAssertEqual(calls.value, 2)
    assertPreservedResult(result, from: fixture.page, recognizedPart: "repeat/second")
    XCTAssertTrue(result.result.warnings.isEmpty)
  }

  func testRepeatedRegionStopsAfterCancellation() async throws {
    let fixture = try fixture()
    let calls = Calls()
    do {
      _ = try await DocumentPDFPageParser.recognize(fixture.page) { image, _, _ in
        XCTAssertTrue(image === fixture.raster.image)
        _ = calls.next()
        throw CancellationError()
      }
      XCTFail("취소 오류를 무시했습니다.")
    } catch is CancellationError { }
    XCTAssertEqual(calls.value, 1)
    XCTAssertEqual(fixture.page.result.images.count, 2)
  }

  func testRepeatedRegionReusesFirstSuccessfulRecognition() async throws {
    let fixture = try fixture()
    let calls = Calls()
    let result = try await DocumentPDFPageParser.recognize(
      fixture.page
    ) { image, location, bounds in
      XCTAssertTrue(image === fixture.raster.image)
      _ = calls.next()
      return [Self.recognized(location: location, bounds: bounds)]
    }
    XCTAssertEqual(calls.value, 1)
    assertPreservedResult(result, from: fixture.page, recognizedPart: "repeat/first")
    XCTAssertTrue(result.result.warnings.isEmpty)
  }

  private func fixture() throws -> (page: DocumentPDFPreparedPage, raster: DocumentPDFRaster) {
    let context = try XCTUnwrap(CGContext(data: nil, width: 840, height: 140,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 840, height: 140))
    let text = NSAttributedString(string: "POLICY MARKER", attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String):
        CTFontCreateWithName("Helvetica-Bold" as CFString, 42, nil)])
    context.textPosition = CGPoint(x: 30, y: 50)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    let raster = DocumentPDFRaster(image: try XCTUnwrap(context.makeImage()))
    let png = try XCTUnwrap(DocumentImageEncoder.png(raster.image))
    let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    let locations = ["repeat/first", "repeat/second"].map {
      DocumentLocation(part: $0, page: 1, bounds: bounds)
    }
    let jobs = locations.map { DocumentPDFImageJob(raster: raster, location: $0) }
    let images = locations.enumerated().map {
      DocumentEmbeddedImage(id: "repeat/\($0.offset)", pngData: png, location: $0.element)
    }
    let page = DocumentPDFPreparedPage(index: 0,
      result: .init(images: images, inspectedImages: 2), raster: raster,
      imageJobs: jobs, extractImages: true)
    return (page, raster)
  }

  private static func recognized(location: DocumentLocation, bounds: CGRect) -> DocumentBlock {
    var located = location
    located.bounds = bounds
    return DocumentBlock(kind: .imageOCR, text: "POLICY MARKER", readingOrder: 0,
      location: located, ocrConfidence: 0.9, ocrOriginalText: "POLICY SOURCE")
  }

  private func assertPreservedResult(
    _ result: DocumentPDFPreparedPage, from prepared: DocumentPDFPreparedPage,
    recognizedPart: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(result.result.images == prepared.result.images, file: file, line: line)
    let imageCount = result.result.blocks.filter { $0.kind == .image }.count
    XCTAssertEqual(imageCount, 2, file: file, line: line)
    let recognized = result.result.blocks.filter { $0.kind == .imageOCR }
    XCTAssertEqual(recognized.count, 1, file: file, line: line)
    XCTAssertTrue(recognized.first?.location.part == recognizedPart, file: file, line: line)
    XCTAssertTrue(recognized.first?.location.bounds == prepared.imageJobs.first?.location.bounds,
      file: file, line: line)
    XCTAssertTrue(recognized.first?.ocrConfidence == 0.9, file: file, line: line)
    XCTAssertTrue(recognized.first?.ocrOriginalText == "POLICY SOURCE", file: file, line: line)
    XCTAssertTrue(result.raster == nil && result.imageJobs.isEmpty, file: file, line: line)
  }
}
