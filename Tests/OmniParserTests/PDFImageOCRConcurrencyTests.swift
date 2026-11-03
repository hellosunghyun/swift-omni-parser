import CoreGraphics
import Foundation
@testable import OmniParser
import Synchronization
import XCTest

final class PDFImageOCRConcurrencyTests: XCTestCase {
  private enum Failure: Error { case recognition, timeout }

  private static func waitUntil(
    _ condition: @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<2_000 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    throw Failure.timeout
  }

  private func fixture(_ bounds: [CGRect]) throws -> DocumentPDFPreparedPage {
    let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let raster = DocumentPDFRaster(image: try XCTUnwrap(context.makeImage()))
    let jobs = bounds.enumerated().map { index, bounds in
      DocumentPDFImageJob(raster: raster,
        location: DocumentLocation(part: "job\(index)", page: 1, bounds: bounds))
    }
    return DocumentPDFPreparedPage(index: 0, imageJobs: jobs, extractImages: true)
  }

  private func pool() async throws -> (DocumentPDFWorkPool, UUID) {
    let pool = DocumentPDFWorkPool(options: .init(maximumConcurrentPDFPages: 3))
    let lease = try await pool.acquire(estimatedBytes: 1)
    return (pool, lease)
  }

  func testOutOfOrderCompletionPreservesJobOrderAndReleasesLeases() async throws {
    try XCTSkipIf(ProcessInfo.processInfo.activeProcessorCount < 2, "동시 작업 슬롯이 필요합니다.")
    let page = try fixture((0..<3).map {
      CGRect(x: Double($0) * 0.2, y: 0, width: 0.1, height: 0.1)
    })
    let (pool, lease) = try await pool()
    let finished = Mutex<[String]>([])
    let observedLeases = Mutex(0)
    let result = try await DocumentPDFScheduling.$pool.withValue(pool) {
      try await DocumentPDFPageParser.recognize(page) { _, location, _ in
        let part = location.part ?? ""
        let active = await pool.snapshot().activePages
        observedLeases.withLock { $0 = max($0, active) }
        if part == "job0" {
          try await Self.waitUntil { finished.withLock { $0.contains("job1") } }
        }
        finished.withLock { $0.append(part) }
        return [DocumentBlock(kind: .imageOCR, text: part, readingOrder: 0, location: location)]
      }
    }
    XCTAssertNotEqual(finished.withLock { $0.first }, "job0")
    XCTAssertGreaterThanOrEqual(observedLeases.withLock { $0 }, 2)
    XCTAssertEqual(result.result.blocks.filter { $0.kind == .imageOCR }.map(\.text),
      ["job0", "job1", "job2"])
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testRepeatedBoundsRetriedAfterEmptyAndError() async throws {
    let bounds = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
    let page = try fixture([bounds, bounds, bounds])
    let (pool, lease) = try await pool()
    let calls = Mutex(0)
    let result = try await DocumentPDFScheduling.$pool.withValue(pool) {
      try await DocumentPDFPageParser.recognize(page) { _, location, _ in
        let call = calls.withLock { $0 += 1; return $0 }
        if call == 1 { return [] }
        if call == 2 { throw Failure.recognition }
        return [DocumentBlock(kind: .imageOCR, text: "NaCl (0.9%)", readingOrder: 0,
          location: location)]
      }
    }
    XCTAssertEqual(calls.withLock { $0 }, 3)
    XCTAssertEqual(result.result.blocks.filter { $0.kind == .imageOCR }.map(\.text),
      ["NaCl (0.9%)"])
    XCTAssertEqual(result.result.warnings.count, 1)
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testSuccessfulDuplicateAfterDistinctJobIsSkipped() async throws {
    let first = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
    let second = CGRect(x: 0.2, y: 0, width: 0.1, height: 0.1)
    let page = try fixture([first, second, first, first])
    let (pool, lease) = try await pool()
    let calls = Mutex<[String]>([])
    let result = try await DocumentPDFScheduling.$pool.withValue(pool) {
      try await DocumentPDFPageParser.recognize(page) { _, location, _ in
        let part = location.part ?? ""
        calls.withLock { $0.append(part) }
        return [DocumentBlock(kind: .imageOCR, text: part, readingOrder: 0, location: location)]
      }
    }
    XCTAssertEqual(Set(calls.withLock { $0 }), Set(["job0", "job1"]))
    XCTAssertEqual(result.result.blocks.filter { $0.kind == .imageOCR }.map(\.text),
      ["job0", "job1"])
    XCTAssertEqual(result.result.blocks.filter { $0.kind == .image }.count, 4)
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testParallelFailurePreservesWarningAndOtherResults() async throws {
    let page = try fixture((0..<3).map {
      CGRect(x: Double($0) * 0.2, y: 0, width: 0.1, height: 0.1)
    })
    let (pool, lease) = try await pool()
    let result = try await DocumentPDFScheduling.$pool.withValue(pool) {
      try await DocumentPDFPageParser.recognize(page) { _, location, _ in
        if location.part == "job1" { throw Failure.recognition }
        return [DocumentBlock(kind: .imageOCR, text: location.part ?? "", readingOrder: 0,
          location: location)]
      }
    }
    XCTAssertEqual(result.result.blocks.filter { $0.kind == .imageOCR }.map(\.text),
      ["job0", "job2"])
    XCTAssertEqual(result.result.warnings.first?.location?.part, "job1")
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testRealCancellationReturnsAdditionalLeases() async throws {
    try XCTSkipIf(ProcessInfo.processInfo.activeProcessorCount < 2, "동시 작업 슬롯이 필요합니다.")
    let page = try fixture((0..<3).map {
      CGRect(x: Double($0) * 0.2, y: 0, width: 0.1, height: 0.1)
    })
    let (pool, lease) = try await pool()
    let started = Mutex(0)
    let task = Task {
      try await DocumentPDFScheduling.$pool.withValue(pool) {
        try await DocumentPDFPageParser.recognize(page) { _, _, _ in
          started.withLock { $0 += 1 }
          try await Task.sleep(for: .seconds(3))
          return []
        }
      }
    }
    do {
      try await Self.waitUntil { started.withLock { $0 >= 2 } }
    } catch {
      task.cancel()
      _ = try? await task.value
      await pool.release(lease)
      throw error
    }
    let during = await pool.snapshot()
    XCTAssertGreaterThanOrEqual(during.activePages, 2)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("취소 오류를 전달해야 합니다.")
    } catch is CancellationError { }
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testChildCancellationCancelsItsSibling() async throws {
    try XCTSkipIf(ProcessInfo.processInfo.activeProcessorCount < 2, "동시 작업 슬롯이 필요합니다.")
    let page = try fixture((0..<2).map {
      CGRect(x: Double($0) * 0.2, y: 0, width: 0.1, height: 0.1)
    })
    let (pool, lease) = try await pool()
    let siblingStarted = Mutex(false)
    let siblingCancelled = Mutex(false)
    do {
      _ = try await DocumentPDFScheduling.$pool.withValue(pool) {
        try await DocumentPDFPageParser.recognize(page) { _, location, _ in
          if location.part == "job0" {
            try await Self.waitUntil { siblingStarted.withLock { $0 } }
            throw CancellationError()
          }
          siblingStarted.withLock { $0 = true }
          do {
            try await Task.sleep(for: .seconds(3))
          } catch is CancellationError {
            siblingCancelled.withLock { $0 = true }
            throw CancellationError()
          }
          return []
        }
      }
      XCTFail("한 작업의 취소를 전파해야 합니다.")
    } catch is CancellationError { }
    XCTAssertTrue(siblingCancelled.withLock { $0 })
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testMemoryBudgetFallsBackToSequentialRecognition() async throws {
    let page = try fixture((0..<3).map {
      CGRect(x: Double($0) * 0.2, y: 0, width: 0.1, height: 0.1)
    })
    let pool = DocumentPDFWorkPool(options: .init(maximumConcurrentPDFPages: 3,
      pdfWorkingMemoryTargetBytes: 1))
    let lease = try await pool.acquire(estimatedBytes: 1)
    let observed = Mutex(0)
    let result = try await DocumentPDFScheduling.$pool.withValue(pool) {
      try await DocumentPDFPageParser.recognize(page) { _, location, _ in
        let state = await pool.snapshot()
        observed.withLock { $0 = max($0, state.activePages) }
        return [DocumentBlock(kind: .imageOCR, text: location.part ?? "", readingOrder: 0,
          location: location)]
      }
    }
    XCTAssertEqual(observed.withLock { $0 }, 1)
    XCTAssertEqual(result.result.blocks.filter { $0.kind == .imageOCR }.map(\.text),
      ["job0", "job1", "job2"])
    await pool.release(lease)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }

  func testTryAcquireDoesNotOvertakeWaitingRequest() async throws {
    let pool = DocumentPDFWorkPool(options: .init(maximumConcurrentPDFPages: 3,
      pdfWorkingMemoryTargetBytes: 100))
    let first = try await pool.acquire(estimatedBytes: 90)
    let waiter = Task { try await pool.acquire(estimatedBytes: 20) }
    do {
      try await Self.waitUntil { await pool.snapshot().waitingRequests > 0 }
    } catch {
      waiter.cancel()
      await pool.release(first)
      _ = try? await waiter.value
      throw error
    }
    let extra = await pool.tryAcquire(estimatedBytes: 1)
    XCTAssertNil(extra)
    await pool.release(first)
    let second = try await waiter.value
    await pool.release(second)
    let state = await pool.snapshot()
    XCTAssertEqual(state.activePages, 0)
    XCTAssertEqual(state.reservedBytes, 0)
  }
}
