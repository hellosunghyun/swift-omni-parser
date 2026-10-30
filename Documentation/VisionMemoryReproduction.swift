// SPDX-License-Identifier: MIT
import CoreGraphics
import CoreML
import CoreText
import CryptoKit
import Darwin
import Dispatch
import Foundation
import ImageIO
import Synchronization
import Vision
import XCTest

/// 자체 생성 이미지로만 비교한다. OmniParser나 원본 small3 문서의 벤치마크가 아니다.
final class VisionMemoryReproductionTests: XCTestCase {
  func testConcurrencyOne() async throws { try await run(concurrency: 1) }
  func testConcurrencyTwo() async throws { try await run(concurrency: 2) }

  private func run(concurrency: Int) async throws {
    let images = try autoreleasepool { try [Self.image(page: true), Self.image(page: false)] }
    let inputHashes = try autoreleasepool {
      try images.map { image in
        Self.hash(try XCTUnwrap(image.dataProvider?.data) as Data)
      }
    }
    let runID = UUID().uuidString
    var reference: [String]?
    // 0은 준비 실행이다. 초기 요청의 관측값도 남기되 성능 요약에서는 제외한다.
    for repetition in 0...5 {
      try Task.checkCancellation()
      let before = VisionMemorySampler.current()
      let sampler = VisionMemorySampler()
      defer { _ = sampler.finish() }
      let start = ProcessInfo.processInfo.systemUptime
      var observations = try await Self.recognize(images, concurrency: concurrency)
      let seconds = ProcessInfo.processInfo.systemUptime - start
      let timeline = sampler.finish()
      let withResults = VisionMemorySampler.current()
      let counts = observations.map(\.count)
      let hashes = try Self.fingerprints(observations)
      observations.removeAll(keepingCapacity: false)
      let afterRelease = VisionMemorySampler.current()
      if let reference {
        XCTAssertEqual(hashes, reference, "반복 간 결과 지문 변화")
      } else {
        reference = hashes
      }
      let peak = [timeline.map { $0[1] }.max() ?? 0, timeline.map { $0[2] }.max() ?? 0]
      XCTAssertGreaterThan(peak[0], 0, "메모리 조회 실패")
      try Self.emit(["runID": runID, "concurrency": concurrency, "repetition": repetition,
        "warmup": repetition == 0, "seconds": seconds, "counts": counts,
        "fingerprints": hashes, "inputSHA256": inputHashes,
        "inputSizes": images.map { [$0.width, $0.height] },
        "beforeBytes": before, "sampledPeakBytes": peak,
        "withResultsBytes": withResults, "afterResultReleaseBytes": afterRelease,
        "timelineMicrosecondsFootprintRSS": timeline, "samplingMilliseconds": 5,
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "configuration": ["revision": 3, "languages": ["ko-KR", "en-US"],
          "accurate": true, "minimumTextHeight": 0,
          "languageCorrection": true, "automaticLanguageDetection": true]])
    }
    try Self.emitDeviceInventory(runID: runID)
  }

  private static func emitDeviceInventory(runID: String) throws {
    let request = Self.request()
    let supported = request.supportedComputeStageDevices
    try Self.emit(["runID": runID, "phase": "post-measurement-device-inventory",
      "allDevices": MLComputeDevice.allComputeDevices.map { Self.deviceName($0) },
      "mainSupported": (supported[.main] ?? []).map { Self.deviceName($0) },
      "postSupported": (supported[.postProcessing] ?? []).map { Self.deviceName($0) },
      "mainAssigned": Self.deviceName(request.computeDevice(for: .main)),
      "postAssigned": Self.deviceName(request.computeDevice(for: .postProcessing))])
  }

  /// 결과 검사는 OCR 시간·최고 메모리 계측이 끝난 뒤 실행한다.
  private static func fingerprints(_ observations: [[RecognizedTextObservation]]) throws
    -> [String] {
    try autoreleasepool {
      try observations.enumerated().map { index, values in
        let text = values.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        let markers = index == 0 ? ["RESEARCH", "연구"] : ["INVOICE", "영수증"]
        for (markerIndex, marker) in markers.enumerated() {
          XCTAssertTrue(text.contains(marker), "자체 마커 불일치: image \(index), marker \(markerIndex)")
        }
        let payload: [[String: Any]] = values.map { observation in
          let box = observation.boundingBox.cgRect
          var row: [String: Any] = ["bounds": [box.minX, box.minY, box.width, box.height]]
          if let candidate = observation.topCandidates(1).first {
            row["text"] = candidate.string
            row["confidence"] = candidate.confidence
          }
          return row
        }
        return Self.hash(try JSONSerialization.data(withJSONObject: payload,
                                                    options: [.sortedKeys]))
      }
    }
  }

  private static func deviceName(_ device: MLComputeDevice?) -> String {
    guard let device else { return "unassigned" }
    switch device {
    case .cpu: return "cpu"
    case .gpu: return "gpu"
    case .neuralEngine: return "neuralEngine"
    @unknown default: return "unknown"
    }
  }

  private static func request() -> RecognizeTextRequest {
    var request = RecognizeTextRequest(.revision3)
    request.recognitionLevel = .accurate
    request.minimumTextHeightFraction = 0
    request.recognitionLanguages = [.init(identifier: "ko-KR"), .init(identifier: "en-US")]
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    return request
  }

  private static func recognize(_ images: [CGImage], concurrency: Int) async throws
    -> [[RecognizedTextObservation]] {
    try await withThrowingTaskGroup(of: (Int, [RecognizedTextObservation]).self) { group in
      var result = [[RecognizedTextObservation]](repeating: [], count: images.count)
      for index in images.indices {
        group.addTask {
          try Task.checkCancellation()
          let request = Self.request()
          return (index, try await request.perform(on: images[index], orientation: .up))
        }
        if index + 1 >= concurrency, let (slot, values) = try await group.next() {
          result[slot] = values
        }
      }
      while let (index, values) = try await group.next() { result[index] = values }
      try Task.checkCancellation()
      return result
    }
  }

  private static func image(page: Bool) throws -> CGImage {
    let width = page ? 1240 : 780
    let height = page ? 1754 : 326
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let lines = page ? ["RESEARCH PAGE MARKER", "연구 자료 문서 분석 결과"] + (1...22).map {
      "연구 문서 분석 실험 결과 자료 확인 \($0)"
    } : ["INVOICE MARKER", "영수증 상품 금액 합계", "TOTAL 125.00"]
    for (index, line) in lines.enumerated() {
      let fontName = "AppleSDGothicNeo-Regular" as CFString
      let font = CTFontCreateWithName(fontName, page ? 32 : 28, nil)
      let value = NSAttributedString(string: line, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
          CGColor(gray: 0, alpha: 1)
      ])
      context.textPosition = CGPoint(x: 40, y: height - 65 - index * (page ? 65 : 80))
      CTLineDraw(CTLineCreateWithAttributedString(value), context)
    }
    return try XCTUnwrap(context.makeImage())
  }

  private static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func emit(_ row: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    let line = try XCTUnwrap(String(data: data, encoding: .utf8))
    print("VISION_MEMORY " + line)
    fflush(stdout)
  }
}

/// 5ms 표본은 순간 최고점을 보장하지 않는다. 계측 자체의 비용도 프로세스 메모리에 포함된다.
private final class VisionMemorySampler: Sendable {
  private let start = ProcessInfo.processInfo.systemUptime
  private let state = Mutex((stopped: false, rows: [[UInt64]]()))
  private let timer: DispatchSourceTimer

  init() {
    let queue = DispatchQueue(label: "vision.memory", qos: .utility)
    timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(5))
    timer.setEventHandler { [weak self] in self?.sample() }
    timer.resume()
    sample()
  }

  deinit { timer.cancel() }

  static func current() -> [UInt64] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                      / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return status == KERN_SUCCESS ? [info.phys_footprint, info.resident_size] : [0, 0]
  }

  private func sample() {
    let bytes = Self.current()
    let microseconds = UInt64((ProcessInfo.processInfo.systemUptime - start) * 1_000_000)
    state.withLock {
      if !$0.stopped { $0.rows.append([microseconds] + bytes) }
    }
  }

  func finish() -> [[UInt64]] {
    sample()
    timer.cancel()
    return state.withLock { $0.stopped = true; return $0.rows }
  }
}
