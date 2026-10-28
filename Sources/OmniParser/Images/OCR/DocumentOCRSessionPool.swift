import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Vision

/// 호출 하나의 작업창에서만 공유하는 비동기 Vision 요청 풀이다.
/// 대여한 요청은 한 작업만 사용하며, 완료한 요청은 최대 2개만 보관한다.
/// 동기 Vision 대기를 협력 스레드에 두지 않고 취소·실패한 요청은 재사용하지 않는다.
nonisolated final class DocumentOCRSessionPool: Sendable {
  private final class Session: Sendable {
    let request: RecognizeTextRequest

    init(language: DocumentOCRLanguage) {
      request = DocumentOCR.makeRequest(language: language)
    }
  }

  /// 풀의 언어는 바꾸지 않아 보관한 요청에 다른 호출의 설정이 섞이지 않는다.
  let language: DocumentOCRLanguage
  private let idle = Mutex<[Session]>([])

  init(language: DocumentOCRLanguage = .automatic) {
    self.language = language
  }

  var cachedSessionCount: Int { idle.withLock { $0.count } }

  func perform(
    image: CGImage, orientation: CGImagePropertyOrientation,
    convert: ([RecognizedTextObservation]) async throws -> [DocumentBlock]
  ) async throws -> [DocumentBlock] {
    try Task.checkCancellation()
    let session = idle.withLock { $0.popLast() } ?? Session(language: language)
    let observations: [RecognizedTextObservation]
    do {
      observations = try await session.request.perform(on: image, orientation: orientation)
    } catch {
      try Task.checkCancellation()
      throw error
    }
    try Task.checkCancellation()
    let result = try await convert(observations)
    try Task.checkCancellation()
    idle.withLock { if $0.count < 2 { $0.append(session) } }
    return result
  }
}
