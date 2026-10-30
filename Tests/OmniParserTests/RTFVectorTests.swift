import CoreGraphics
import Foundation
@testable import OmniParser
import XCTest

final class RTFVectorTests: XCTestCase {
  func testPureWMFAndEMFRenderRealColoredPixels() async throws {
    for (data, _) in vectors() {
      let rendered = try await render(data)
      let image = try XCTUnwrap(rendered)
      XCTAssertGreaterThan(image.width, 0)
      XCTAssertGreaterThan(image.height, 0)
      XCTAssertLessThanOrEqual(image.width * image.height, 2_000_000)
      let pixels = try pixelCounts(image)
      XCTAssertGreaterThan(pixels.red, 500)
      XCTAssertGreaterThan(pixels.black, 100)
      XCTAssertGreaterThan(pixels.white, 1_000)
    }
  }

  func testPureVectorTextSupportsKoreanEnglishOCR() async throws {
    for (data, format) in vectors() {
      let rendered = try await render(data)
      let image = try XCTUnwrap(rendered)
      let result = try await DocumentParser.parse(.image(image, orientation: .up),
        options: .init(performOCR: true))
      XCTAssertTrue(result.fullText.contains("VECTOR"), "\(format): 영문 벡터 OCR 누락")
      XCTAssertTrue(result.fullText.contains("한글"), "\(format): 한글 벡터 OCR 누락")
      XCTAssertTrue(result.fullText.contains("TEST"), "\(format): 마지막 벡터 OCR 누락")
      XCTAssertTrue(result.images.isEmpty)
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testRTFVectorPictureKeepsLocationAndFourOptionCombinations() async throws {
    for (data, format) in vectors() {
      let source = RTFVectorFixtures.rtf(data, format: format)
      let offset = try XCTUnwrap(source.range(of: Data("{\\pict".utf8))).lowerBound
      for images in [false, true] {
        for ocr in [false, true] {
          let result = try await parse(source, images: images, ocr: ocr)
          XCTAssertEqual(result.images.count, images ? 1 : 0)
          XCTAssertEqual(result.blocks.contains { $0.kind == .imageOCR }, ocr)
          for image in result.images {
            XCTAssertTrue(image.location.part?.contains("byte[\(offset)]") == true)
          }
          if ocr {
            let block = try XCTUnwrap(result.blocks.first { $0.kind == .imageOCR })
            XCTAssertTrue(block.location.part?.contains("byte[\(offset)]") == true)
            XCTAssertTrue(result.fullText.contains("VECTOR"))
          }
          XCTAssertTrue(result.fullText.hasPrefix("Before"))
          XCTAssertTrue(result.fullText.hasSuffix("After"))
          XCTAssertFalse(result.fullText.contains("OMNIRTF"))
          TestFixtures.assertTextConsistency(result)
        }
      }
    }
  }

  func testOLEVectorPreviewPreservesHostLocationAndText() async throws {
    for (data, format) in vectors() {
      let source = RTFVectorFixtures.rtf(data, format: format, objectPreview: true)
      let offset = try XCTUnwrap(source.range(of: Data("{\\object".utf8))).lowerBound
      let result = try await parse(source, images: true, ocr: true)
      XCTAssertEqual(result.images.count, 1)
      XCTAssertTrue(result.images[0].location.part?
        .hasPrefix("rtf/byte[\(offset)]/object[1]/preview") == true)
      XCTAssertTrue(result.fullText.contains("VECTOR"))
      XCTAssertTrue(result.fullText.hasSuffix("After"))
      XCTAssertTrue(result.warnings.contains { $0.code == .unsupportedElement })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testVectorPreferredOverPNGDoesNotDuplicateOCR() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    for (data, format) in vectors() {
      let source = RTFVectorFixtures.rtfWithFallback(data, format: format, png: png)
      let result = try await parse(source, images: true, ocr: true)
      XCTAssertEqual(result.images.count, 1)
      XCTAssertTrue(result.fullText.contains("VECTOR"))
      XCTAssertFalse(result.fullText.contains("IMAGE OCR MARKER"))
      XCTAssertFalse(result.warnings.contains { $0.code == .extractionFailed })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testExistingRTFWMFCompatibilityPicturesCanRenderDirectly() async throws {
    let data = try Data(contentsOf:
      TestFixtures.url("RealWorld/rtf/real-rtf-03-testRTFRegularImages.rtf"))
    let prepared = try DocumentRTFPictureReader.read(data, options: .init(extractImages: true))
    let backups = prepared.pictures.compactMap(\.backup)
    XCTAssertEqual(backups.count, 2)
    for backup in backups {
      let rendered = try await render(backup.data)
      let image = try XCTUnwrap(rendered)
      XCTAssertGreaterThan(image.width * image.height, 0)
    }
  }

  func testMalformedVectorKeepsFollowingTextAndValidImage() async throws {
    let broken = Data(RTFVectorFixtures.emf().prefix(50))
    let first = try XCTUnwrap(String(data: RTFVectorFixtures.rtf(broken, format: "emfblip"),
                                    encoding: .utf8))
    let second = try XCTUnwrap(String(data: RTFVectorFixtures.rtf(RTFVectorFixtures.wmf(),
      format: "wmetafile8"), encoding: .utf8))
    let body = first.dropFirst(7).dropLast() + second.dropFirst(7).dropLast()
    let source = Data(("{\\rtf1 " + body + "Final marker}").utf8)
    let result = try await parse(source, images: true, ocr: false)
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.fullText.contains("Final marker"))
    XCTAssertTrue(result.warnings.contains { $0.code == .extractionFailed })
    TestFixtures.assertTextConsistency(result)
  }

  func testVectorPixelLimitPreservesRTFBody() async throws {
    for (data, format) in vectors() {
      let result = try await DocumentParser.parse(
        .data(RTFVectorFixtures.rtf(data, format: format), fileName: "pixels.rtf"),
        options: .init(extractImages: true, maximumImagePixels: 1))
      XCTAssertTrue(result.images.isEmpty)
      XCTAssertTrue(result.fullText.contains("After"))
      XCTAssertTrue(result.warnings.contains { $0.code == .resourceLimitReached })
    }
  }

  func testVectorRecordLimitRejectsOversizedRecordList() async throws {
    for data in [RTFVectorFixtures.wmf(extraRecords: 10_001),
                 RTFVectorFixtures.emf(extraRecords: 10_001)] {
      do {
        _ = try await render(data)
        XCTFail("벡터 record 한도를 넘는 입력을 렌더링했습니다.")
      } catch { XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge) }
    }
  }

  func testRendererCancellationReleasesQueueForNextRender() async throws {
    let data = RTFVectorFixtures.emf()
    let task = Task { try await render(data) }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("취소된 벡터 렌더가 완료됐습니다.")
    } catch { XCTAssertTrue(error is CancellationError) }
    let rendered = try await render(RTFVectorFixtures.wmf())
    XCTAssertNotNil(rendered)
  }

  func testVectorCancellationAndBatchOrder() async throws {
    let source = RTFVectorFixtures.rtf(RTFVectorFixtures.wmf(), format: "wmetafile8")
    let task = Task { try await parse(source, images: true, ocr: true) }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("취소한 벡터 파싱이 성공했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    let inputs = [DocumentInput.data(Data("First marker".utf8), fileName: "first.txt"),
                  .data(source, fileName: "vector.rtf"),
                  .data(Data("Last marker".utf8), fileName: "last.txt")]
    let results = try await DocumentParser.parseBatch(inputs,
      options: .init(extractImages: true, maximumConcurrentDocuments: 2))
    XCTAssertEqual(results.count, 3)
    for (index, expected) in ["First marker", "Before", "Last marker"].enumerated() {
      guard case .success(let result) = results[index] else {
        return XCTFail("배치의 \(index)번째 결과가 실패했습니다.")
      }
      XCTAssertTrue(result.fullText.contains(expected))
      TestFixtures.assertTextConsistency(result)
    }
  }

  private func vectors() -> [(Data, String)] {
    [(RTFVectorFixtures.wmf(), "wmetafile8"), (RTFVectorFixtures.emf(), "emfblip")]
  }

  private func render(_ data: Data) async throws -> CGImage? {
    try await DocumentVectorRenderer.render(data, maximumPixels: 2_000_000)
  }

  private func parse(_ data: Data, images: Bool, ocr: Bool) async throws -> DocumentParseResult {
    try await DocumentParser.parse(.data(data, fileName: "vector.rtf"),
                                   options: .init(extractImages: images, performOCR: ocr))
  }

  private struct PixelCounts {
    var red = 0
    var black = 0
    var white = 0
  }

  private func pixelCounts(_ image: CGImage) throws -> PixelCounts {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width,
        height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    var counts = PixelCounts()
    for index in stride(from: 0, to: bytes.count, by: 16) {
      let (red, green, blue) = (bytes[index], bytes[index + 1], bytes[index + 2])
      if red > 200 && green < 60 && blue < 60 { counts.red += 1 }
      if red < 60 && green < 60 && blue < 60 { counts.black += 1 }
      if red > 240 && green > 240 && blue > 240 { counts.white += 1 }
    }
    return counts
  }
}
