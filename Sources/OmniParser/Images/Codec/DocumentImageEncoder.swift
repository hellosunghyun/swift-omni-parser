import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// 추출한 비트맵을 방향 메타데이터가 포함된 PNG로 보관한다.
/// 원본 압축 스트림을 그대로 돌려주는 기능은 아니다.
nonisolated enum DocumentImageEncoder {
  private static let encodingQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "OmniParser.PNGEncoding"
    queue.qualityOfService = .default
    queue.maxConcurrentOperationCount = 2
    return queue
  }()

  private final class Cancellation: Sendable {
    private let flag = Mutex(false)
    var isCancelled: Bool { flag.withLock { $0 } }
    func cancel() { flag.withLock { $0 = true } }
  }

  /// HEIC의 지연 디코딩이 finalize에서 OS default-QoS 작업을 기다릴 수 있다.
  /// 호출 Task를 suspend하고 최대 2개만 처리한다. 시작한 ImageIO 호출은 강제로 중단하지 않는다.
  static func pngAsync(
    _ image: CGImage, orientation: CGImagePropertyOrientation = .up,
    encode: @escaping @Sendable (CGImage, CGImagePropertyOrientation) -> Data? = {
      png($0, orientation: $1)
    }
  ) async throws -> Data? {
    let cancellation = Cancellation()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      let result: Data? = await withCheckedContinuation { continuation in
        let operation = BlockOperation {
          let data = cancellation.isCancelled ? nil : autoreleasepool {
            encode(image, orientation)
          }
          continuation.resume(returning: data)
        }
        operation.qualityOfService = .default
        encodingQueue.addOperation(operation)
      }
      // 취소된 pending 작업은 encode를 생략하고, 실행 중 취소는 native 호출 종료 후 전달한다.
      try Task.checkCancellation()
      return result
    } onCancel: {
      cancellation.cancel()
    }
  }

  static func png(
    _ image: CGImage, orientation: CGImagePropertyOrientation = .up
  ) -> Data? {
    let data = NSMutableData()
    guard let target = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(target, image, [
      kCGImagePropertyOrientation: orientation.rawValue
    ] as CFDictionary)
    guard CGImageDestinationFinalize(target) else { return nil }
    return data as Data
  }
}
