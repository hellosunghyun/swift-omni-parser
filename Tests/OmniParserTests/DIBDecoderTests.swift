import CoreGraphics
import Foundation
@testable import OmniParser
import XCTest

final class DIBDecoderTests: XCTestCase {
  func testBottomUpAndTopDown24BitRowsHaveSameOrientation() throws {
    let red = [UInt8](arrayLiteral: 0, 0, 255, 0)
    let blue = [UInt8](arrayLiteral: 255, 0, 0, 0)
    var bottomUp = dib(width: 1, height: 2, bits: 24, pixels: blue + red)
    bottomUp.replaceSubrange(20..<24, with: word(0))
    let topDown = dib(width: 1, height: -2, bits: 24, pixels: red + blue)
    for data in [bottomUp, topDown] {
      let image = try XCTUnwrap(DocumentDIBDecoder.decode(data, maximumPixels: 2))
      XCTAssertEqual(image.width, 1)
      XCTAssertEqual(image.height, 2)
      XCTAssertEqual(try rgba(image), [255, 0, 0, 255, 0, 0, 255, 255])
    }
  }

  func test32BitAndPalettedImages() throws {
    let image = try XCTUnwrap(DocumentDIBDecoder.decode(
      dib(width: 1, height: 1, bits: 32, pixels: [0, 0, 255, 0]), maximumPixels: 1))
    XCTAssertEqual(Array(try rgba(image).prefix(3)), [255, 0, 0])
    let palette: [UInt8] = [0, 0, 0, 0, 0, 0, 255, 0]
    for (bits, packed) in [(1, UInt8(0x80)), (4, UInt8(0x10)), (8, UInt8(1))] {
      let data = dib(width: 1, height: 1, bits: bits,
                     pixels: [packed, 0, 0, 0], palette: palette)
      XCTAssertEqual(try rgba(XCTUnwrap(DocumentDIBDecoder.decode(data, maximumPixels: 1))),
                     [255, 0, 0, 255])
    }
  }

  func testExtendedHeadersAndDefaultPalette() throws {
    let simple = dib(width: 1, height: 1, bits: 24, pixels: [0, 0, 255, 0])
    for header in [52, 56, 108, 124] {
      var data = word(header) + simple.subdata(in: 4..<40)
      data.append(Data(repeating: 0, count: header - 40))
      data.append(simple.suffix(4))
      let image = try XCTUnwrap(DocumentDIBDecoder.decode(data, maximumPixels: 1))
      XCTAssertEqual(try rgba(image), [255, 0, 0, 255])
    }
    var paletted = dib(width: 1, height: 1, bits: 1, pixels: [0x80, 0, 0, 0],
                       palette: [0, 0, 0, 0, 0, 0, 255, 0])
    paletted.replaceSubrange(32..<36, with: word(0))
    XCTAssertNotNil(try DocumentDIBDecoder.decode(paletted, maximumPixels: 1))
    XCTAssertThrowsError(try DocumentDIBDecoder.decode(
      dib(width: 1, height: 1, bits: 1, pixels: [0x80, 0, 0, 0]), maximumPixels: 1))
  }

  func testInvalidLengthsDimensionsAndPaletteAreRejected() {
    let valid = dib(width: 1, height: 1, bits: 24, pixels: [0, 0, 255, 0])
    var excessiveSize = valid
    excessiveSize.replaceSubrange(20..<24, with: word(100))
    var paletteTooLarge = valid
    paletteTooLarge.replaceSubrange(32..<36, with: word(Int(UInt32.max)))
    let invalid = [Data(valid.prefix(39)), Data(valid.dropLast()),
                   excessiveSize, paletteTooLarge,
                   dib(width: 0, height: 1, bits: 24, pixels: [0, 0, 0, 0]),
                   dib(width: 1, height: 0, bits: 24, pixels: [0, 0, 0, 0]),
                   dib(width: -1, height: 1, bits: 24, pixels: [0, 0, 0, 0])]
    for data in invalid {
      XCTAssertThrowsError(try DocumentDIBDecoder.decode(data, maximumPixels: Int.max))
    }
  }

  func testUnsupportedHeaderAndCompressionReturnNil() throws {
    XCTAssertNil(try DocumentDIBDecoder.decode(Data([1, 2, 3]), maximumPixels: 1))
    var compressed = dib(width: 1, height: 1, bits: 24, pixels: [0, 0, 255, 0])
    compressed.replaceSubrange(16..<20, with: word(1))
    XCTAssertNil(try DocumentDIBDecoder.decode(compressed, maximumPixels: 1))
  }

  func testPixelLimitAndHugeDimensionsDoNotAllocateRaster() {
    let valid = dib(width: 1, height: 2, bits: 24, pixels: [UInt8](repeating: 0, count: 8))
    for limit in [0, 1] {
      XCTAssertThrowsError(try DocumentDIBDecoder.decode(valid, maximumPixels: limit)) {
        XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
      }
    }
    let huge = dib(width: Int(Int32.max), height: Int(Int32.min), bits: 32, pixels: [])
    XCTAssertThrowsError(try DocumentDIBDecoder.decode(huge, maximumPixels: Int.max))
  }

  private func dib(
    width: Int, height: Int, bits: Int, pixels: [UInt8], palette: [UInt8] = []
  ) -> Data {
    var result = word(40) + word(width) + word(height)
    result.append(contentsOf: [1, 0, UInt8(bits), 0])
    result.append(word(0) + word(pixels.count) + word(0) + word(0))
    result.append(word(palette.count / 4) + word(0))
    result.append(contentsOf: palette + pixels)
    return result
  }

  private func word(_ value: Int) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }

  private func rgba(_ image: CGImage) throws -> [UInt8] {
    let context = try XCTUnwrap(CGContext(
      data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
    return Array(UnsafeBufferPointer(start: pixels, count: image.width * image.height * 4))
  }
}
