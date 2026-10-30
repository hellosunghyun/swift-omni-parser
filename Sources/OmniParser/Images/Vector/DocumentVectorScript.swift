import CoreFoundation
import Foundation
import JavaScriptCore

/// 공개 JavaScriptCore API만 사용한다. JS 루프는 vendored AST 패치의 협력형 guard를 호출한다.
nonisolated enum DocumentVectorScript {
  struct Converted {
    let svg: String
    let hasUnsupportedElements: Bool
  }

  static func convert(_ data: Data) throws -> String { try convertDetailed(data).svg }

  static func convertDetailed(_ data: Data) throws -> Converted {
    try Task.checkCancellation()
    guard let context = JSContext(),
      let url = Bundle.module.url(forResource: "renderer", withExtension: "js",
                                  subdirectory: "Vector") else {
      throw DocumentParsingError.malformedDocument
    }
    let deadline = Date().addingTimeInterval(10)
    var operations = 0
    var stopped = false
    let budget: @convention(block) () -> Bool = {
      operations += 1
      if operations > 500_000 || Date() > deadline || Task.isCancelled { stopped = true }
      return !stopped
    }
    let base64: @convention(block) (String) -> String = {
      guard $0.utf16.count <= 8 * 1024 * 1024 else { stopped = true; return "" }
      return Data($0.utf16.map { UInt8(truncatingIfNeeded: $0) }).base64EncodedString()
    }
    let decode: @convention(block) (String, [NSNumber]) -> String = { label, values in
      let bytes = Data(values.map { $0.uint8Value })
      let identifiers: [String: UInt32] = [
        "euc-kr": 0x0422, "windows-949": 0x0422, "shift_jis": 0x0420,
        "gbk": 0x0421, "big5": 0x0423, "utf-8": 0x08000100
      ]
      let encoding = identifiers[label.lowercased()] ?? 0x0500
      let raw = CFStringConvertEncodingToNSStringEncoding(encoding)
      return String(data: bytes, encoding: String.Encoding(rawValue: raw)) ?? ""
    }
    context.setObject(budget, forKeyedSubscript: "__omniContinue" as NSString)
    context.setObject(base64, forKeyedSubscript: "btoa" as NSString)
    context.setObject(decode, forKeyedSubscript: "__omniDecode" as NSString)
    context.evaluateScript(bootstrap)
    context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
    context.evaluateScript(adaptations)
    guard context.exception == nil else { throw DocumentParsingError.malformedDocument }
    context.setObject(input(data, context: context), forKeyedSubscript: "__omniInput" as NSString)
    let result = context.evaluateScript(
      "module.exports.renderToSvg(new Uint8Array(__omniInput),{viewWidth:1024,viewHeight:1024})")
    try Task.checkCancellation()
    guard !stopped, context.objectForKeyedSubscript("__omniFault")?.toBool() != true else {
      throw DocumentParsingError.inputTooLarge
    }
    guard context.objectForKeyedSubscript("__omniMalformed")?.toBool() != true,
      context.exception == nil, let svg = result?.toString(),
      svg.utf8.count <= 16 * 1024 * 1024 else {
      throw DocumentParsingError.malformedDocument
    }
    return Converted(svg: svg,
      hasUnsupportedElements: context.objectForKeyedSubscript("__omniUnsupported")?
        .toBool() == true)
  }

  private static func input(_ data: Data, context: JSContext) -> JSValue? {
    data.withUnsafeBytes { buffer in
      let storage = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 1)
      storage.copyMemory(from: buffer.baseAddress!, byteCount: data.count)
      guard let value = JSObjectMakeArrayBufferWithBytesNoCopy(
        context.jsGlobalContextRef, storage, data.count,
        { pointer, _ in pointer?.deallocate() }, nil, nil) else {
        storage.deallocate()
        return nil
      }
      return JSValue(jsValueRef: value, in: context)
    }
  }

  private static let bootstrap = """
    var module={exports:{}};
    var __omniUnsupported=false, __omniMalformed=false;
    var console={log:function(){},error:function(){__omniMalformed=true;},
                 warn:function(){__omniMalformed=true;}};
    function __omniBudget(){if(!__omniContinue())throw Error('Vector resource limit');}
    var TextDecoder=function(label){this.label=label||'utf-8';};
    TextDecoder.prototype.decode=function(bytes){
      if(bytes.length>65536){__omniFault=true;throw Error('Vector text limit');}
      return __omniDecode(this.label,Array.from(bytes));
    };
    var Buffer={from:function(bytes){return {toString:function(){
      var chunks=[];for(var i=0;i<bytes.length;i+=8192){__omniBudget();
        chunks.push(String.fromCharCode.apply(null,bytes.slice(i,i+8192)));}
      return btoa(chunks.join(''));
    }};}};
    var __omniAllocated=0, __omniFault=false, __omniNodeBytes=0, __omniNodeCount=0;
    function __omniNodes(array){
      array.push=function(){
        __omniBudget();
        for(var i=0;i<arguments.length;i++){
          __omniNodeBytes+=String(arguments[i]).length*2;__omniNodeCount++;
        }
        if(__omniNodeBytes>16777216||__omniNodeCount>50000){
          __omniFault=true;throw Error('Vector output limit');
        }
        return Array.prototype.push.apply(this,arguments);
      };return array;
    }
    ['Uint8Array','Uint8ClampedArray','Uint16Array','Uint32Array','Int8Array','Int16Array',
     'Int32Array','Float32Array','Float64Array'].forEach(function(name){
      var original=globalThis[name];
      globalThis[name]=new Proxy(original,{construct:function(target,args){
        __omniBudget();
        var first=args[0];
        var count=typeof first==='number'?first:(first&&first.byteLength||first&&first.length||0);
        var size=count*target.BYTES_PER_ELEMENT;
        if(!Number.isFinite(size)||size<0||size>16777216||(__omniAllocated+=size)>67108864)
          {__omniFault=true;throw Error('Vector allocation limit');}
        return Reflect.construct(target,args);
      }});
      original.prototype.constructor=globalThis[name];
    });
    """

  private static let adaptations = """
    (function(){
      var proto=module.exports.WmfDrawer.prototype;
      var original=proto.readStringFromData;
      proto.readStringFromData=function(data,offset,length){
        var label=this.getDbcsCharsetLabel(this.currentCharset);
        if(label){
          if(length>65536){__omniFault=true;throw Error('Vector text limit');}
          return new TextDecoder(label).decode(data.slice(offset,offset+length));
        }
        return original.call(this,data,offset,length);
      };
    })();
    """

}
