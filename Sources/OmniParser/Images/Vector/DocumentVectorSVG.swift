import CoreGraphics
import Foundation
import ImageIO

/// JS가 만든 SVG도 불신한다. 외부 참조·능동 콘텐츠·엔티티와 과도한 노드를 거부한다.
nonisolated enum DocumentVectorSVG {
  static func validate(_ svg: String, maximumPixels: Int) throws -> CGSize {
    guard svg.utf8.count <= 16 * 1024 * 1024 else {
      throw DocumentParsingError.inputTooLarge
    }
    let upper = svg.uppercased()
    guard !upper.contains("<!DOCTYPE"), !upper.contains("<!ENTITY") else {
      throw DocumentParsingError.malformedDocument
    }
    let delegate = Validator(maximumPixels: maximumPixels)
    let parser = XMLParser(data: Data(svg.utf8))
    parser.shouldResolveExternalEntities = false
    parser.externalEntityResolvingPolicy = .never
    parser.delegate = delegate
    guard parser.parse(), !delegate.rejected, delegate.validReferences(),
      let size = delegate.size else {
      throw delegate.limited ? DocumentParsingError.inputTooLarge
        : DocumentParsingError.malformedDocument
    }
    guard size.width <= 8192, size.height <= 8192,
      Int(size.width) <= min(maximumPixels, 4_000_000) / Int(size.height) else {
      throw DocumentParsingError.inputTooLarge
    }
    return size
  }

  private final class Validator: NSObject, XMLParserDelegate {
    var size: CGSize?
    var rejected = false
    var limited = false
    private var nodes = 0
    private var remainingImagePixels: Int
    private var identifiers: Set<String> = []
    private var ancestors: [String?] = []
    private var references: [String: Set<String>] = [:]

    init(maximumPixels: Int) { remainingImagePixels = min(maximumPixels, 4_000_000) }

    func validReferences() -> Bool {
      var visited: Set<String> = []
      var active: Set<String> = []
      func visit(_ name: String, depth: Int) -> Bool {
        if depth > 64 || active.contains(name) { return false }
        if visited.contains(name) { return true }
        active.insert(name)
        for target in references[name] ?? [] {
          guard identifiers.contains(target), visit(target, depth: depth + 1) else { return false }
        }
        active.remove(name)
        visited.insert(name)
        return true
      }
      return references.keys.allSatisfy { visit($0, depth: 0) }
    }

    func parser(
      _ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?
    ) { if !ancestors.isEmpty { ancestors.removeLast() } }

    private let elements: Set<String> = [
      "svg", "g", "defs", "path", "rect", "ellipse", "circle", "line", "polyline", "polygon",
      "text", "tspan", "image", "clipPath", "linearGradient", "radialGradient", "stop", "pattern"
    ]
    private let attributes: Set<String> = [
      "xmlns", "xmlns:xlink", "width", "height", "viewBox", "version", "id", "x", "y",
      "x1", "x2", "y1", "y2", "cx", "cy", "r", "rx", "ry", "d", "points", "transform",
      "fill", "fill-rule", "fill-opacity", "stroke", "stroke-width", "stroke-linecap",
      "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset",
      "stroke-opacity", "opacity", "clip-path", "clip-rule", "clipPathUnits", "font-family",
      "font-size", "font-style", "font-weight", "text-anchor", "dominant-baseline",
      "dx", "dy", "textLength", "lengthAdjust", "preserveAspectRatio", "href", "xlink:href",
      "gradientUnits", "gradientTransform", "offset", "stop-color", "stop-opacity",
      "spreadMethod", "fx", "fy", "patternUnits", "patternContentUnits", "patternTransform"
    ]

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName: String?, attributes values: [String: String]
    ) {
      nodes += 1
      if nodes > 50_000 || ancestors.count >= 128 { limited = true; reject(parser); return }
      guard elements.contains(elementName) else { reject(parser); return }
      if nodes == 1 {
        guard elementName == "svg", let width = values["width"].flatMap(Double.init),
          let height = values["height"].flatMap(Double.init),
          width.isFinite, height.isFinite, width >= 1, height >= 1,
          width <= 8192, height <= 8192 else { reject(parser); return }
        size = CGSize(width: ceil(width), height: ceil(height))
      }
      if let identifier = values["id"] {
        guard identifier.count <= 128, identifiers.insert(identifier).inserted else {
          reject(parser); return
        }
      }
      ancestors.append(values["id"])
      validateAttributes(values, element: elementName, parser: parser)
    }

    private func validateAttributes(
      _ values: [String: String], element: String, parser: XMLParser
    ) {
      for (name, value) in values {
        guard attributes.contains(name) else { reject(parser); return }
        if value.utf8.count > 2 * 1024 * 1024 { limited = true; reject(parser); return }
        if name == "href" || name == "xlink:href" {
          guard validReference(value, image: element == "image") else {
            reject(parser); return
          }
        }
        if value.lowercased().contains("url(") {
          guard value.range(of: "^url\\(#[A-Za-z0-9_-]+\\)$",
                            options: .regularExpression) != nil else { reject(parser); return }
          let target = String(value.dropFirst(5).dropLast())
          for owner in ancestors.compactMap({ $0 }) + ["__root"] {
            references[owner, default: []].insert(target)
          }
        }
      }
    }

    private func validReference(_ value: String, image: Bool) -> Bool {
      guard image else { return false }
      let prefixes = ["data:image/png;base64,", "data:image/jpeg;base64,",
                      "data:image/bmp;base64,"]
      guard let prefix = prefixes.first(where: { value.hasPrefix($0) }) else { return false }
      guard let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetCount(source) == 1,
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0, width <= remainingImagePixels / height else {
        limited = true
        return false
      }
      remainingImagePixels -= width * height
      return true
    }

    private func reject(_ parser: XMLParser) { rejected = true; parser.abortParsing() }
  }
}
