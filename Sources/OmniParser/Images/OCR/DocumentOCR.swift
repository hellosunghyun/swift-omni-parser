import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 모든 형식에서 공통으로 사용하는 온디바이스 Vision OCR이다.
/// 한영 인식 결과를 좌상단 기준 좌표와 읽기 순서가 있는 블록으로 변환한다.
nonisolated enum DocumentOCR {
  /// parse·parseBatch가 만든 풀을 자식 작업에 전달한다. 전역으로 모든 문서의 세션을 공유하지 않는다.
  @TaskLocal static var sessions: DocumentOCRSessionPool?

  static func recognize(
    image: CGImage,
    orientation: CGImagePropertyOrientation,
    location: DocumentLocation = DocumentLocation()
  ) async throws -> [DocumentBlock] {
    try Task.checkCancellation()
    let pool = sessions ?? DocumentOCRSessionPool()
    return try await pool.perform(image: image, orientation: orientation) {
      try await blocks($0, image: image, orientation: orientation, location: location)
    }
  }

  /// 정확도·언어 보정은 유지하며 호출자가 선택한 언어 정책만 적용한다.
  static func makeRequest(language: DocumentOCRLanguage = .automatic) -> RecognizeTextRequest {
    var request = RecognizeTextRequest(.revision3)
    // Swift Vision 기본값(1/32)과 VN 요청 기본값(0)이 달라 작은 글자 기준을 명시한다.
    request.minimumTextHeightFraction = 0
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if language == .english {
      request.recognitionLanguages = [.init(identifier: "en-US")]
    } else {
      request.recognitionLanguages = [.init(identifier: "ko-KR"), .init(identifier: "en-US")]
    }
    request.automaticallyDetectsLanguage = language == .automatic
    return request
  }

  /// 유효한 Vision 좌표만 unit 영역과 교차시켜 좌상단 기준으로 바꾼다. 위치 미상은 nil이다.
  static func normalizedBounds(_ bounds: CGRect) -> CGRect? {
    guard !bounds.isNull, !bounds.isInfinite,
      bounds.origin.x.isFinite, bounds.origin.y.isFinite,
      bounds.size.width.isFinite, bounds.size.height.isFinite,
      bounds.size.width > 0, bounds.size.height > 0,
      (bounds.origin.x + bounds.size.width).isFinite,
      (bounds.origin.y + bounds.size.height).isFinite
    else { return nil }
    let clipped: CGRect
    if bounds.minX >= 0, bounds.minY >= 0, bounds.maxX <= 1, bounds.maxY <= 1 {
      // 이미 유효한 좌표는 폭·높이를 다시 계산하지 않아 기존 값을 그대로 보존한다.
      clipped = bounds
    } else {
      clipped = bounds.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    guard !clipped.isNull, !clipped.isEmpty,
      clipped.origin.x.isFinite, clipped.origin.y.isFinite,
      clipped.size.width.isFinite, clipped.size.height.isFinite
    else { return nil }
    return CGRect(x: clipped.minX, y: 1 - clipped.maxY,
      width: clipped.width, height: clipped.height)
  }

  /// Vision의 좌하단 원점을 좌상단으로 뒤집는다. 부분 그림의 페이지 좌표 변환은 호출 측이 담당한다.
  private static func blocks(
    _ source: [RecognizedTextObservation], image: CGImage,
    orientation: CGImagePropertyOrientation, location: DocumentLocation
  ) async throws -> [DocumentBlock] {
    let enhanced = try await DocumentNumericOCR.refine(
      image: image, orientation: orientation, observations: source)
    var blocks: [DocumentBlock] = source.enumerated().compactMap { order, observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      var located = location
      // 위치를 복원할 수 없어도 인식한 문구와 신뢰도는 보존한다.
      located.bounds = normalizedBounds(observation.boundingBox.cgRect)
      return DocumentBlock(
        kind: .imageOCR,
        text: enhanced[observation.uuid]?.text ?? candidate.string,
        readingOrder: order,
        location: located,
        ocrConfidence: enhanced[observation.uuid]?.confidence ?? candidate.confidence,
        ocrOriginalText: enhanced[observation.uuid] == nil ? nil : candidate.string
      )
    }
    blocks.sortInGeometricReadingOrder()
    return blocks
  }
}
