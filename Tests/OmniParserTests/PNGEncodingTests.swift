import CoreGraphics
import Darwin
import Foundation
import ImageIO
@testable import OmniParser
import Synchronization
import XCTest

final class PNGEncodingTests: XCTestCase {
  private struct Counters: Sendable {
    var calls = 0
    var active = 0
    var peak = 0
    var qosClasses: [qos_class_t] = []
  }

  private final class State: Sendable {
    let values = Mutex(Counters())
  }

  func testAsyncPNGPreservesSyncBytesForOrientations() async throws {
    let image = try makeImage()
    for orientation in [CGImagePropertyOrientation.up, .right, .leftMirrored] {
      let expected = try XCTUnwrap(DocumentImageEncoder.png(image, orientation: orientation))
      let actual = try await DocumentImageEncoder.pngAsync(image, orientation: orientation)
      XCTAssertTrue(actual == expected, "기존 sync PNG 바이트와 다릅니다.")
    }
  }

  func testPreCancelledTaskDoesNotInvokeEncoder() async throws {
    let calls = State()
    let image = try makeImage()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await DocumentImageEncoder.pngAsync(image) { _, _ in
        calls.values.withLock { $0.calls += 1 }
        return Data([1])
      }
    }
    do {
      _ = try await task.value
      XCTFail("취소된 작업이 PNG를 반환했습니다.")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(calls.values.withLock { $0.calls }, 0)
  }

  func testQueueLimitsConcurrencyAndSkipsCancelledPendingRequest() async throws {
    let counters = State()
    let gate = DispatchSemaphore(value: 0)
    let firstTwoStarted = expectation(description: "첫 PNG 작업 2개 시작")
    firstTwoStarted.expectedFulfillmentCount = 2
    let image = try makeImage()
    let encode: @Sendable (CGImage, CGImagePropertyOrientation) -> Data? = { _, _ in
      counters.values.withLock {
        $0.calls += 1
        $0.active += 1
        $0.peak = max($0.peak, $0.active)
        $0.qosClasses.append(qos_class_self())
      }
      firstTwoStarted.fulfill()
      gate.wait()
      counters.values.withLock { $0.active -= 1 }
      return Data([1])
    }
    let first = Task { try await DocumentImageEncoder.pngAsync(image, encode: encode) }
    let second = Task { try await DocumentImageEncoder.pngAsync(image, encode: encode) }
    defer { gate.signal(); gate.signal() }
    await fulfillment(of: [firstTwoStarted], timeout: 3)
    let pending = Task { try await DocumentImageEncoder.pngAsync(image, encode: encode) }
    await Task.yield()
    pending.cancel()
    gate.signal()
    gate.signal()
    _ = try await first.value
    _ = try await second.value
    do {
      _ = try await pending.value
      XCTFail("취소된 pending 작업이 PNG를 반환했습니다.")
    } catch { XCTAssertTrue(error is CancellationError) }
    counters.values.withLock {
      XCTAssertEqual($0.calls, 2)
      XCTAssertEqual($0.peak, 2)
      XCTAssertTrue($0.qosClasses.allSatisfy { $0 == QOS_CLASS_DEFAULT })
    }
  }

  func testCancellationAfterEncodeStartsDoesNotReturnStalePNG() async throws {
    let gate = DispatchSemaphore(value: 0)
    let started = expectation(description: "PNG encode 시작")
    let image = try makeImage()
    let task = Task {
      try await DocumentImageEncoder.pngAsync(image) { _, _ in
        started.fulfill()
        gate.wait()
        return Data([1])
      }
    }
    defer { gate.signal() }
    await fulfillment(of: [started], timeout: 3)
    task.cancel()
    gate.signal()
    do {
      _ = try await task.value
      XCTFail("실행 중 취소 후 PNG를 반환했습니다.")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  private func makeImage() throws -> CGImage {
    let context = try XCTUnwrap(CGContext(data: nil, width: 3, height: 2,
      bitsPerComponent: 8, bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0.25, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
    return try XCTUnwrap(context.makeImage())
  }
}
