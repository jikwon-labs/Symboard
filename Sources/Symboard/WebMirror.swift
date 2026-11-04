import Foundation
import WebKit

/// 공유 보기에서 웹 타일 페이지를 옮겨 그리기(15차). 맥의 WKWebView 에 rrweb 기록기를 넣어
/// 페이지 구조와 바뀐 부분만 보내고, 보기 화면이 rrweb 재생기로 같은 페이지를 직접 그린다.
/// 기록기는 페이지와 떨어진 격리 세계(`WKContentWorld.defaultClient`)에서 돈다.
/// 페이지 스크립트는 기록기나 중계 통로에 손대지 못한다.
enum WebMirror {
    /// 기록기가 보내는 메시지 통로 이름(격리 세계 전용).
    static let handlerName = "symMirror"
    static let world = WKContentWorld.defaultClient

    /// 앱 번들(`Contents/Resources/rrweb`)에서, 없으면 소스 폴더(`swift run`)에서 읽는다.
    static func resource(_ name: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "rrweb"),
           let data = try? Data(contentsOf: url) { return data }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try? Data(contentsOf: repo.appendingPathComponent("Resources/rrweb/\(name).js"))
    }

    static let replaySource: Data? = resource("replay")

    /// 페이지에 넣는 스크립트. 이미 돌고 있으면 전체 장면만 다시 보낸다.
    /// 바뀐 것은 40ms 씩 모아 JSON 글 하나로 보낸다. 새 전체 장면(Meta)이 시작되면 앞 묶음을 먼저 보내고
    /// `r: true` 로 알려, 서버가 새로 온 사람에게 줄 기록을 그 장면부터 다시 모은다.
    static let injectScript: String? = {
        guard let data = resource("record"), let record = String(data: data, encoding: .utf8) else { return nil }
        return """
        (function () {
          if (window.__symMirror) { window.__symMirror.full(); return 'again'; }
          var R = (function () { var define, exports, module, g = {};
            (function () {
        \(record)
            }).call(g);
            return g.rrwebRecord; })();
          if (!R || !R.record) return 'missing';
          var buf = [], reset = false, timer = null;
          function post() {
            timer = null;
            if (!buf.length) return;
            var d = JSON.stringify(buf), r = reset; buf = []; reset = false;
            try { window.webkit.messageHandlers.\(handlerName).postMessage({ r: r, d: d }); } catch (e) {}
          }
          var stop = R.record({
            emit: function (e) {
              if (e.type === 4) { post(); reset = true; }
              buf.push(e);
              if (!timer) timer = setTimeout(post, 40);
            },
            sampling: { mousemove: false, mouseInteraction: false, scroll: 50, media: 800, input: 'last' },
            recordCanvas: false, collectFonts: false, inlineImages: false, recordCrossOriginIframes: false,
            slimDOMOptions: { script: true, comment: true, headFavicon: true, headWhitespace: true, headMetaSocial: true, headMetaRobots: true, headMetaHttpEquiv: true, headMetaVerification: true, headMetaAuthorship: true }
          });
          window.__symMirror = {
            full: function () { R.record.takeFullSnapshot(true); },
            stop: function () { if (stop) stop(); stop = null; post(); window.__symMirror = null; }
          };
          return 'started';
        })();
        """
    }()

    static let stopScript = "if (window.__symMirror) { window.__symMirror.stop(); } 'stopped';"
    static let fullScript = "if (window.__symMirror) { window.__symMirror.full(); 'full'; } else { 'off'; }"
    static let aliveScript = "window.__symMirror ? 'on' : 'off';"

    /// 기록기가 보낸 한 묶음. reset 이면 새 전체 장면부터 시작한다.
    enum Message {
        case events(reset: Bool, json: String)
        /// 이 페이지는 옮겨 그릴 수 없다(넣기 실패). 보기 화면은 찍은 화면으로 대신한다.
        case off
    }
}
