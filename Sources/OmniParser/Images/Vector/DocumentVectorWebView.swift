import CoreGraphics
import Foundation
import WebKit

/// 정적인 SVG를 창에 붙이지 않은 WebKit으로 PDF화한 뒤 CoreGraphics로 그린다.
/// 작업별 WebView를 해제하며 timeout·취소·delegate 응답은 continuation을 한 번만 끝낸다.
@MainActor
final class DocumentVectorWebView: NSObject, WKNavigationDelegate {
  private static var sharedStore: WKWebsiteDataStore?
  private static var idleCleanup: Task<Void, Never>?
  private var webView: WKWebView?
  private var completion: CheckedContinuation<CGImage, Error>?
  private var timeout: Task<Void, Never>?
  private let size: CGSize
  private var cancelled = false

  private init(size: CGSize) { self.size = size }

  static func render(_ svg: String, size: CGSize) async throws -> CGImage {
    let job = DocumentVectorWebView(size: size)
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        job.start(svg, completion: continuation)
      }
    } onCancel: {
      Task { @MainActor in job.cancel() }
    }
  }

  private func start(_ svg: String, completion: CheckedContinuation<CGImage, Error>) {
    self.completion = completion
    if cancelled { finish(.failure(CancellationError())); return }
    let configuration = WKWebViewConfiguration()
    Self.idleCleanup?.cancel()
    let store = Self.sharedStore ?? WKWebsiteDataStore.nonPersistent()
    Self.sharedStore = store
    configuration.websiteDataStore = store
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
    webView = view
    view.navigationDelegate = self
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(10)) } catch { return }
      self?.finish(.failure(DocumentParsingError.inputTooLarge))
    }
    let body = svg.hasPrefix("<?xml")
      ? svg.components(separatedBy: "?>").dropFirst().joined(separator: "?>") : svg
    let policy = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; "
      + "script-src 'none'; "
      + "connect-src 'none'; font-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'"
    view.loadHTMLString(
      "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
      + "<meta http-equiv='Content-Security-Policy' content=\"\(policy)\">"
      + "<style>html,body{margin:0;overflow:hidden}</style></head><body>\(body)</body></html>",
      baseURL: nil)
  }

  private func cancel() { cancelled = true; finish(.failure(CancellationError())) }

  private func finish(_ result: Result<CGImage, Error>) {
    guard let continuation = completion else { return }
    completion = nil
    timeout?.cancel()
    timeout = nil
    webView?.navigationDelegate = nil
    webView?.stopLoading()
    webView = nil
    // 연속 처리 중에만 메모리 세션을 재사용하고 idle 뒤에는 캐시 보유를 끝낸다.
    Self.idleCleanup?.cancel()
    Self.idleCleanup = Task {
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
      guard !Task.isCancelled else { return }
      Self.sharedStore = nil
      Self.idleCleanup = nil
    }
    continuation.resume(with: result)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard completion != nil else { return }
    let configuration = WKPDFConfiguration()
    configuration.rect = CGRect(origin: .zero, size: size)
    webView.createPDF(configuration: configuration) { [weak self] result in
      guard let self, self.completion != nil else { return }
      self.finish(result.flatMap { data in
        Result { try autoreleasepool { try self.rasterize(data) } }
      })
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(.failure(DocumentParsingError.malformedDocument))
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) { finish(.failure(DocumentParsingError.malformedDocument)) }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failure(DocumentParsingError.malformedDocument))
  }

  private func rasterize(_ data: Data) throws -> CGImage {
    guard data.count <= 32 * 1024 * 1024, let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider), document.numberOfPages == 1,
      let page = document.page(at: 1),
      let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DocumentParsingError.malformedDocument
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    context.drawPDFPage(page)
    guard let image = context.makeImage() else { throw DocumentParsingError.malformedDocument }
    return image
  }
}
