import AppKit
import SwiftUI
import WebKit
import SymboardCore

/// 웹 타일 옆에 뜨는 인스펙터 타일. Elements(DOM 나무·상자 모델)와 Console(로그·식 실행).
/// WKWebView 내장 인스펙터는 공개 API 로 타일 안에 넣을 수 없어서, 페이지에 JS 를 돌려 직접 보여 준다.
final class InspectorContent: NodeContent {
    let host: NSView
    let inspector: InspectorModel
    var view: NSView { host }

    init(node: BoardNode, model: AppModel) {
        inspector = InspectorModel(webID: node.text.flatMap(UUID.init(uuidString:)))
        host = CanvasHostingView(rootView: InspectorView(model: inspector).environment(\.colorScheme, .dark))
    }

    func sync(node: BoardNode) {}
}

struct DOMNode: Identifiable {
    var id: String { path.map(String.init).joined(separator: ".") }
    var path: [Int]
    var tag: String
    var elementID: String
    var classes: String
    var childCount: Int
    var children: [DOMNode]
}

@MainActor
final class InspectorModel: ObservableObject {
    let webID: UUID?
    @Published var tab = "Elements"
    @Published var root: DOMNode?
    @Published var expanded: Set<String> = ["", "0", "1"]
    @Published var selected: [Int]?
    @Published var box: [String: String] = [:]
    @Published var expr = ""
    @Published var evalLog: [(String, String)] = []
    @Published var error: String?

    init(webID: UUID?) { self.webID = webID }

    var web: WebContent? {
        guard let id = webID, let c = (NSApp.delegate as? AppDelegate)?.windowController else { return nil }
        return c.currentCanvas?.nodeViews[id]?.content as? WebContent
    }

    static let treeJS = """
    (function(){function n(e,d,p){var o={t:e.tagName.toLowerCase(),i:e.id||'',c:(typeof e.className==='string'?e.className:'').trim().split(/\\s+/).filter(Boolean).slice(0,3).join('.'),n:e.children.length,p:p,k:[]};if(d<7){for(var i=0;i<Math.min(e.children.length,60);i++)o.k.push(n(e.children[i],d+1,p.concat([i])));}return o;}return JSON.stringify(n(document.documentElement,0,[]));})()
    """

    func refresh() {
        guard let w = web?.webView else { error = "The web tile is not on this board."; return }
        error = nil
        w.evaluateJavaScript(Self.treeJS) { [weak self] result, err in
            guard let self else { return }
            if let s = result as? String, let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.root = Self.parse(obj)
            } else { self.error = err?.localizedDescription ?? "No page loaded." }
        }
    }

    static func parse(_ o: [String: Any]) -> DOMNode {
        DOMNode(path: (o["p"] as? [Int]) ?? [], tag: o["t"] as? String ?? "?", elementID: o["i"] as? String ?? "",
                classes: o["c"] as? String ?? "", childCount: o["n"] as? Int ?? 0,
                children: (o["k"] as? [[String: Any]] ?? []).map(parse))
    }

    func select(_ path: [Int]) {
        selected = path
        let js = """
        (function(p){var e=document.documentElement;for(var i=0;i<p.length;i++){e=e.children[p[i]];if(!e)return null;}
        document.querySelectorAll('[data-sym-hl]').forEach(function(x){x.style.outline=x.getAttribute('data-sym-hl');x.removeAttribute('data-sym-hl');});
        e.setAttribute('data-sym-hl', e.style.outline||''); e.style.outline='2px solid #F05A38';
        var s=getComputedStyle(e), r=e.getBoundingClientRect();
        return JSON.stringify({w:Math.round(r.width),h:Math.round(r.height),m:s.marginTop+' '+s.marginRight+' '+s.marginBottom+' '+s.marginLeft,
        b:s.borderTopWidth+' '+s.borderRightWidth+' '+s.borderBottomWidth+' '+s.borderLeftWidth,
        pd:s.paddingTop+' '+s.paddingRight+' '+s.paddingBottom+' '+s.paddingLeft,d:s.display,pos:s.position,f:s.fontSize+' '+s.fontFamily.split(',')[0],col:s.color,bg:s.backgroundColor});})(\(path))
        """
        web?.webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let s = result as? String, let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            self?.box = o.mapValues { "\($0)" }
        }
    }

    func evaluate() {
        let e = expr.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty, let w = web?.webView else { return }
        expr = ""
        w.evaluateJavaScript("(function(){try{var r=(0,eval)(\(Self.jsString(e)));return typeof r==='string'?r:JSON.stringify(r);}catch(x){return 'Error: '+x.message;}})()") { [weak self] r, err in
            self?.evalLog.append((e, (r as? String) ?? err?.localizedDescription ?? "undefined"))
        }
    }

    static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        return String(String(decoding: data ?? Data(), as: UTF8.self).dropFirst().dropLast())
    }
}

struct InspectorView: View {
    @ObservedObject var model: InspectorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(["Elements", "Console"], id: \.self) { t in
                    Button(t) { model.tab = t }.buttonStyle(ChipStyle(on: model.tab == t))
                }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim)
            }
            .padding(8)
            Divider().overlay(Color.symBorder)
            if let e = model.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.symDim).padding(10) }
            if model.tab == "Elements" { elements } else { console }
        }
        .background(Color.symSurface)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.refresh() } }
    }

    var flat: [(DOMNode, Int)] {
        var out: [(DOMNode, Int)] = []
        func walk(_ n: DOMNode, _ d: Int) {
            out.append((n, d))
            if model.expanded.contains(n.id) { n.children.forEach { walk($0, d + 1) } }
        }
        if let r = model.root { walk(r, 0) }
        return out
    }

    var elements: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(flat, id: \.0.id) { n, d in
                        HStack(spacing: 4) {
                            Image(systemName: n.childCount == 0 ? "circle.fill" : (model.expanded.contains(n.id) ? "chevron.down" : "chevron.right"))
                                .font(.system(size: n.childCount == 0 ? 3 : 8)).frame(width: 10).foregroundStyle(Color.symDim)
                                .onTapGesture { if model.expanded.contains(n.id) { model.expanded.remove(n.id) } else { model.expanded.insert(n.id) } }
                            (Text("<\(n.tag)").foregroundColor(Color(hex: "#F28AB2"))
                             + Text(n.elementID.isEmpty ? "" : " id").foregroundColor(Color(hex: "#E9C46A"))
                             + Text(n.elementID.isEmpty ? "" : "=\"\(n.elementID)\"").foregroundColor(Color(hex: "#56C2C9"))
                             + Text(n.classes.isEmpty ? "" : " class").foregroundColor(Color(hex: "#E9C46A"))
                             + Text(n.classes.isEmpty ? "" : "=\"\(n.classes)\"").foregroundColor(Color(hex: "#56C2C9"))
                             + Text(">").foregroundColor(Color(hex: "#F28AB2")))
                                .font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, CGFloat(d) * 12 + 6).padding(.vertical, 1)
                        .background(model.selected == n.path ? Color.symAccent.opacity(0.18) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(n.path) }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 150)
            if !model.box.isEmpty {
                Divider().overlay(Color.symBorder)
                boxModel
            }
        }
    }

    var boxModel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BOX MODEL").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#C8862E").opacity(0.45)).frame(width: 180, height: 76)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#E9C46A").opacity(0.5)).frame(width: 144, height: 54)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#6FCF97").opacity(0.5)).frame(width: 112, height: 34)
                Text("\(model.box["w"] ?? "?") × \(model.box["h"] ?? "?")").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#56A8F5").opacity(0.6)))
            }
            .frame(maxWidth: .infinity)
            Group {
                row("margin", model.box["m"]); row("padding", model.box["pd"]); row("display", model.box["d"])
            }
        }
        .padding(10)
    }

    func row(_ k: String, _ v: String?) -> some View {
        HStack { Text(k).foregroundStyle(Color.symDim); Spacer(); Text(v ?? "-").foregroundStyle(Color.symText) }
            .font(.system(size: 10, design: .monospaced))
    }

    var console: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if let w = model.web {
                        ConsoleLines(state: w.state)
                    }
                    ForEach(Array(model.evalLog.enumerated()), id: \.offset) { _, e in
                        Text("› \(e.0)").foregroundStyle(Color.symDim)
                        Text(e.1).foregroundStyle(Color.symText)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            HStack {
                Text("›").foregroundStyle(Color.symAccent)
                TextField("", text: $model.expr, prompt: Text("Evaluate in page").foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symText)
                    .onSubmit { model.evaluate() }
            }
            .padding(8).background(Color.symRaised)
        }
    }
}

struct ConsoleLines: View {
    @ObservedObject var state: WebTileState
    var body: some View {
        ForEach(Array(state.console.enumerated()), id: \.offset) { _, l in
            Text(l.text).foregroundStyle(l.level == "error" ? Color(hex: "#E8564A") : (l.level == "warn" ? Color(hex: "#E9C46A") : Color.symText))
        }
    }
}
