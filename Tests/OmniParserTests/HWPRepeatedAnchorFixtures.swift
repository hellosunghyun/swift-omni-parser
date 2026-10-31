import Foundation

/// 자체 PNG 하나를 문단 또는 문단·두 셀에서 참조하는 자체 OWPML 컨테이너다.
enum HWPRepeatedAnchorFixtures {
  static func make(
    png: Data, before: String, between: String, after: String, includeCells: Bool = false
  ) -> Data {
    let version = """
    <hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version"
    tagetApplication="WORDPROCESSOR" major="5" minor="1" micro="1" buildNumber="0"/>
    """
    let manifest = """
    <opf:package xmlns:opf="http://www.idpf.org/2007/opf/"><opf:manifest>
    <opf:item id="header" href="Contents/header.xml" media-type="application/xml"/>
    <opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>
    <opf:item id="image1" href="BinData/image1.png" media-type="image/png"/>
    </opf:manifest><opf:spine><opf:itemref idref="section0"/></opf:spine></opf:package>
    """
    let header = """
    <hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" version="1.5" secCnt="1">
    <hh:beginNum page="1" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>
    <hh:refList><hh:charProperties itemCnt="1">\
    <hh:charPr id="0" height="1000" textColor="#000000"/>
    </hh:charProperties><hh:paraProperties itemCnt="1"><hh:paraPr id="0">
    <hh:align horizontal="LEFT"/></hh:paraPr></hh:paraProperties><hh:styles itemCnt="1">
    <hh:style id="0" type="PARA" name="Normal" engName="Normal" paraPrIDRef="0"
    charPrIDRef="0" nextStyleIDRef="0"/></hh:styles></hh:refList></hh:head>
    """
    let placement = includeCells ? tableParagraph() : pictureParagraph()
    let section = """
    <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section"
    xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph"
    xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core">
    <hp:p id="1" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:secPr id=""><hp:pagePr width="59528" height="84186"/></hp:secPr>
    <hp:t>\(before)</hp:t></hp:run></hp:p>
    <hp:p id="2" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:pic id="42" zOrder="0" numberingType="FIGURE" textWrap="TOP_AND_BOTTOM">
    <hp:sz width="60000" height="12000" widthRelTo="ABSOLUTE" heightRelTo="ABSOLUTE"/>
    <hp:pos treatAsChar="1" vertRelTo="PARA" horzRelTo="PARA"/>
    <hc:img binaryItemIDRef="image1"/></hp:pic></hp:run></hp:p>
    <hp:p id="3" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:t>\(between)</hp:t></hp:run></hp:p>
    \(placement)
    <hp:p id="5" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:t>\(after)</hp:t></hp:run></hp:p></hs:sec>
    """
    return makeZIP([("mimetype", Data("application/hwp+zip".utf8)),
      ("version.xml", Data(version.utf8)), ("Contents/content.hpf", Data(manifest.utf8)),
      ("Contents/header.xml", Data(header.utf8)), ("Contents/section0.xml", Data(section.utf8)),
      ("BinData/image1.png", png)])
  }

  private static func pictureParagraph() -> String {
    """
    <hp:p id="4" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:pic id="43" zOrder="1" numberingType="FIGURE" textWrap="TOP_AND_BOTTOM">
    <hp:sz width="60000" height="12000" widthRelTo="ABSOLUTE" heightRelTo="ABSOLUTE"/>
    <hp:pos treatAsChar="1" vertRelTo="PARA" horzRelTo="PARA"/>
    <hc:img binaryItemIDRef="image1"/></hp:pic></hp:run></hp:p>
    """
  }

  /// 고정 CoreHwp HwpxObjectFixture와 HwpxTableMapper의 table/cell 어휘를 사용한다.
  private static func tableParagraph() -> String {
    """
    <hp:p id="4" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:tbl id="50" zOrder="1" numberingType="TABLE" textWrap="TOP_AND_BOTTOM"
    pageBreak="CELL" repeatHeader="0" rowCnt="1" colCnt="2" cellSpacing="0">
    <hp:sz width="60000" height="18000" widthRelTo="ABSOLUTE" heightRelTo="ABSOLUTE"/>
    <hp:pos treatAsChar="1" vertRelTo="PARA" horzRelTo="PARA"/>
    <hp:tr>\(cellXML(column: 0))\(cellXML(column: 1))</hp:tr>
    </hp:tbl></hp:run></hp:p>
    """
  }

  private static func cellXML(column: Int) -> String {
    """
    <hp:tc name="" header="0"><hp:subList vertAlign="TOP">
    <hp:p id="\(100 + column * 2)" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:t>Cell \(column + 1)</hp:t></hp:run></hp:p>
    <hp:p id="\(101 + column * 2)" paraPrIDRef="0" styleIDRef="0"><hp:run charPrIDRef="0">
    <hp:pic id="\(43 + column)" zOrder="\(column + 1)"
    numberingType="FIGURE" textWrap="TOP_AND_BOTTOM">
    <hp:sz width="30000" height="6000" widthRelTo="ABSOLUTE" heightRelTo="ABSOLUTE"/>
    <hp:pos treatAsChar="1" vertRelTo="PARA" horzRelTo="PARA"/>
    <hc:img binaryItemIDRef="image1"/></hp:pic></hp:run></hp:p>
    </hp:subList><hp:cellAddr colAddr="\(column)" rowAddr="0"/>
    <hp:cellSpan colSpan="1" rowSpan="1"/><hp:cellSz width="30000" height="18000"/>
    </hp:tc>
    """
  }

  /// HWPX 앵커·XML 보안 회귀가 함께 사용하는 stored ZIP·정상 CRC 빌더다.
  static func makeZIP(_ entries: [(String, Data)]) -> Data {
    func number(_ value: Int, _ count: Int = 4) -> Data {
      Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    func crc(_ data: Data) -> Int {
      var value: UInt32 = 0xFFFF_FFFF
      for byte in data {
        value ^= UInt32(byte)
        for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 0 ? 0 : 0xEDB8_8320) }
      }
      return Int(~value)
    }
    var local = Data(), central = Data()
    for (name, payload) in entries {
      let nameBytes = Data(name.utf8), offset = local.count, checksum = crc(payload)
      local.append(number(0x0403_4B50))
      for value in [20, 0, 0, 0, 0] { local.append(number(value, 2)) }
      for value in [checksum, payload.count, payload.count] { local.append(number(value)) }
      local.append(number(nameBytes.count, 2)); local.append(number(0, 2))
      local.append(nameBytes); local.append(payload)
      central.append(number(0x0201_4B50))
      for value in [20, 20, 0, 0, 0, 0] { central.append(number(value, 2)) }
      for value in [checksum, payload.count, payload.count] { central.append(number(value)) }
      for value in [nameBytes.count, 0, 0, 0, 0] { central.append(number(value, 2)) }
      central.append(number(0)); central.append(number(offset)); central.append(nameBytes)
    }
    var end = number(0x0605_4B50)
    for value in [0, 0, entries.count, entries.count] { end.append(number(value, 2)) }
    end.append(number(central.count)); end.append(number(local.count)); end.append(number(0, 2))
    return local + central + end
  }
}
