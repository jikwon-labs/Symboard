import Foundation

/// 보기 전용 공유 링크를 열면 보이는 화면(14차). 앱의 보드와 같은 모양으로 그린다:
/// 점 격자 캔버스 위에 노드(콘솔·스티키·글자·도형·체크리스트·칸반·캘린더 등)를 같은 자리·크기로 놓고,
/// 그룹 프레임·흐르는 점 연결선·다이어그램 화살표·펜 획도 같은 색과 굵기로 그린다. 끌어서 이동, 휠·핀치로 확대.
/// 콘솔은 xterm.js(jsDelivr, 무결성 해시 고정)로 실시간 화면을, claude 는 스크롤되는 대화 보기도 보인다.
/// 같은 주소의 `events` 흐름에서 board(작업공간 배치)·meta(콘솔 상태)·out(출력)·chat(대화)을 받는다.
/// 조작 링크(`/c/…`)로 열면 맥에서 허용한 콘솔에만 입력할 수 있다: 터미널에 직접 치거나(키 그대로), 대화 보기 아래 입력칸으로 보낸다.
enum ShareViewerPage {
    static let csp = "default-src 'none'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; "
        + "style-src 'unsafe-inline' https://cdn.jsdelivr.net; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'"

    static let html = #"""
<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<meta name="robots" content="noindex">
<title>Symboard view</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css"
      integrity="sha384-8Xk9wy/gzEDUKrXtrmCFa2bBuK3BpjpDuL/p0SeKQX19Khl/M+lHOgD/CyYf7efP" crossorigin="anonymous">
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js"
        integrity="sha384-M169f14mRZOXm3hD/v2Ti0ThIT/RnAQagXA9nlE15yHAtrW19gdePJh/HaTzUOe/" crossorigin="anonymous"></script>
<style>
  /* Theme.swift 와 같은 색 */
  :root, [data-theme="dark"] {
    --canvas:#0F0E0D; --dot:#2A2724; --surface:#171615; --raised:#1F1D1B; --border:#2E2B28; --nodeBorder:#3A2E2A;
    --text:#ECE7E2; --dim:#8F8882; --ink3:#5A5550; --accent:#F05A38; --termBg:#121110; --termText:#ECE7E2; --shadow:0,0,0;
  }
  [data-theme="light"] {
    --canvas:#F5F2EE; --dot:#D9D2CA; --surface:#FFFFFF; --raised:#F1EDE8; --border:#DED7CF; --nodeBorder:#D8C9C2;
    --text:#211D1A; --dim:#77706A; --ink3:#B7AEA6; --shadow:90,74,64;
  }
  * { box-sizing:border-box; }
  html, body { margin:0; height:100%; overflow:hidden; background:var(--canvas); color:var(--text);
    font:13px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; -webkit-font-smoothing:antialiased; }
  .hand { font-family:"Chalkboard SE", "ChalkboardSE-Regular", Noteworthy, "Marker Felt", "Comic Sans MS", cursive; }
  .mono { font-family:ui-monospace, "SF Mono", Menlo, Monaco, monospace; }

  #viewport { position:fixed; inset:0; overflow:hidden; touch-action:none; cursor:grab; }
  #viewport.panning { cursor:grabbing; }
  #world { position:absolute; left:0; top:0; transform-origin:0 0; }
  svg.layer { position:absolute; left:0; top:0; width:1px; height:1px; overflow:visible; pointer-events:none; }

  /* 노드 */
  .node { position:absolute; border-radius:12px; overflow:hidden; border:1px solid var(--nodeBorder); background:var(--surface); cursor:default; }
  .node.term { background:var(--termBg); }
  .node.waiting { border:2px solid #E9C46A; }
  .node.flat { border:0; background:transparent; overflow:visible; border-radius:4px; }
  .nhead { height:28px; display:flex; align-items:center; gap:0; padding:0 6px 0 8px; background:var(--surface); white-space:nowrap; cursor:grab; }
  .glyph { width:18px; height:18px; border-radius:5px; display:flex; align-items:center; justify-content:center; font:700 10px ui-monospace, Menlo, monospace; flex:none; }
  .chev { width:12px; margin:0 4px 0 1px; color:var(--dim); flex:none; display:flex; justify-content:center; }
  .kicon { width:14px; height:14px; margin:0 8px 0 2px; color:var(--dim); flex:none; }
  .sdot { width:7px; height:7px; border-radius:50%; margin-right:6px; flex:none; }
  .ntitle { font-size:12px; font-weight:600; overflow:hidden; text-overflow:ellipsis; flex:0 1 auto; min-width:10px; }
  .nrole { font-size:11px; color:var(--dim); margin-left:6px; overflow:hidden; text-overflow:ellipsis; flex:1 1 auto; min-width:0; }
  .spacer { flex:1 1 auto; }
  .pill { height:16px; border-radius:8px; display:flex; align-items:center; padding:0 7px 0 7px; gap:4px; flex:none; margin-left:6px;
    font:700 9px ui-monospace, Menlo, monospace; letter-spacing:.8px; }
  .pill i { width:5px; height:5px; border-radius:50%; display:block; }
  .hbtn { width:22px; height:20px; display:flex; align-items:center; justify-content:center; color:var(--dim); border-radius:5px; flex:none; margin-left:2px; cursor:pointer; background:none; border:0; padding:0; }
  .hbtn:hover { background:rgba(127,127,127,.15); color:var(--text); }
  .hbtn.on { color:var(--accent); }
  .nbody { position:absolute; left:0; right:0; top:28px; bottom:0; }
  .flat .nbody { top:0; }

  /* 콘솔 몸통 */
  .tbox { position:absolute; inset:0; padding:4px 6px; overflow:hidden; }
  .tbox .xterm { height:100%; }
  .chat { position:absolute; inset:0; overflow-y:auto; padding:14px 16px 18px; display:flex; flex-direction:column; gap:10px;
    background:var(--termBg); color:var(--termText); overscroll-behavior:contain; touch-action:pan-y; font-size:13px; line-height:1.5; cursor:auto; }
  .msg { white-space:pre-wrap; word-break:break-word; }
  .msg.user { align-self:flex-end; max-width:85%; background:rgba(240,90,56,.13); border:1px solid rgba(240,90,56,.32); padding:7px 11px; border-radius:12px 12px 3px 12px; }
  .msg.tool { font:11px/1.4 ui-monospace, Menlo, monospace; color:#8F8882; padding-left:10px; border-left:2px solid #2E2B28; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .chat .none { color:#8F8882; text-align:center; padding:30px 0; }
  .jump { position:sticky; bottom:0; align-self:center; border:1px solid #2E2B28; background:#1F1D1B; color:#ECE7E2; border-radius:999px; padding:4px 12px; font:inherit; font-size:11px; cursor:pointer; }
  .node:not(.typing) .xterm .xterm-helper-textarea { display:none; }
  .node.typing { box-shadow:0 0 0 1px rgba(111,207,151,.55); }
  .typing-badge { display:none; height:16px; border-radius:8px; padding:0 7px; margin-left:6px; flex:none; align-items:center;
    font:700 9px ui-monospace, Menlo, monospace; letter-spacing:.8px; color:#fff; background:rgba(111,207,151,.85); }
  .node.typing .typing-badge { display:flex; }
  .lockbar { position:absolute; left:0; right:0; bottom:0; display:none; align-items:center; gap:8px; padding:9px 12px; font-size:12px;
    color:#8F8882; background:rgba(23,22,21,.94); border-top:1px solid #2E2B28; z-index:2; }
  .node.locked .lockbar { display:flex; }
  .compose { position:absolute; left:0; right:0; bottom:0; display:none; gap:8px; padding:10px 12px; background:#171615; border-top:1px solid #2E2B28; }
  .node.typing.chatmode .compose { display:flex; }
  .node.typing.chatmode .chat { bottom:58px; }
  .compose textarea { flex:1; resize:none; height:38px; max-height:120px; border-radius:9px; border:1px solid #2E2B28; background:#121110; color:#ECE7E2;
    font:13px/1.4 -apple-system, BlinkMacSystemFont, sans-serif; padding:9px 10px; outline:none; }
  .compose textarea:focus { border-color:#F05A38; }
  .compose button { border:0; border-radius:9px; background:#F05A38; color:#fff; font:600 12px -apple-system, sans-serif; padding:0 14px; cursor:pointer; }

  /* 스티키 */
  .sticky .txt { position:absolute; left:0; top:0; padding:12px 10px 22px; font-size:17px; line-height:24px; white-space:pre-wrap; word-break:break-word; overflow:hidden; }
  /* 글자 */
  .textnode { white-space:pre-wrap; word-break:break-word; padding:0 5px; line-height:1.2; }
  .placeholder { color:var(--dim); opacity:.5; }
  /* 체크리스트 */
  .ck-head { display:flex; align-items:center; gap:12px; padding:12px; }
  .ck-ring { width:30px; height:30px; position:relative; flex:none; }
  .ck-ring span { position:absolute; inset:0; display:flex; align-items:center; justify-content:center; font:700 11px ui-monospace, Menlo, monospace; }
  .ck-items { padding:0 0 8px; overflow:hidden; }
  .ck-item { display:flex; align-items:center; gap:10px; padding:6px 12px; font-size:13px; }
  .ck-item.done span { color:var(--dim); text-decoration:line-through; }
  /* 칸반 */
  .kb { position:absolute; inset:0; display:flex; gap:10px; padding:10px; overflow:hidden; background:var(--surface); }
  .kb-col { flex:1 1 0; min-width:0; display:flex; flex-direction:column; gap:8px; padding:10px; border-radius:12px; border:1px solid var(--border); background:color-mix(in srgb, var(--raised) 60%, transparent); overflow:hidden; }
  .kb-h { display:flex; align-items:center; gap:6px; font-size:11px; font-weight:700; letter-spacing:.6px; }
  .kb-h i { width:7px; height:7px; border-radius:50%; }
  .kb-h small { font:11px ui-monospace, Menlo, monospace; color:var(--dim); font-weight:400; letter-spacing:0; }
  .kb-card { position:relative; padding:8px 8px 8px 11px; border-radius:9px; background:var(--surface); border:1px solid var(--border); font-size:12px; font-weight:500; }
  .kb-card b { position:absolute; left:0; top:6px; bottom:6px; width:3px; border-radius:2px; }
  .kb-card.done { color:var(--dim); }
  .kb-card small { display:block; margin-top:4px; font-size:10px; color:var(--dim); font-weight:400; }
  .kb-empty { text-align:center; color:var(--dim); font-size:11px; padding:18px 0; }
  /* 캘린더 */
  .cal { position:absolute; inset:0; padding:10px 12px; display:flex; flex-direction:column; }
  .cal-h { font-size:15px; font-weight:700; margin-bottom:8px; }
  .cal-g { flex:1; display:grid; grid-template-columns:repeat(7, 1fr); grid-auto-rows:1fr; gap:2px; }
  .cal-w { font-size:10px; color:var(--dim); text-align:center; padding-bottom:4px; }
  .cal-d { border-radius:6px; padding:3px 4px; font-size:11px; overflow:hidden; background:color-mix(in srgb, var(--raised) 70%, transparent); }
  .cal-d.out { opacity:.35; }
  .cal-d.today b { background:var(--accent); color:#fff; border-radius:8px; padding:0 5px; }
  .cal-e { font-size:9px; border-radius:3px; padding:0 3px; margin-top:2px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; color:#fff; }
  /* 웹·기타 */
  .web-bar { margin:8px; height:28px; border-radius:8px; background:var(--raised); display:flex; align-items:center; padding:0 10px; font-size:12px; color:var(--dim); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .ph { position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:6px; color:var(--dim); font-size:12px; text-align:center; padding:16px; }
  .imgnode img { width:100%; height:100%; object-fit:contain; display:block; pointer-events:none; user-select:none; }

  /* 그룹 프레임 */
  .group { position:absolute; pointer-events:none; }
  .group .gbody { position:absolute; left:0; right:0; top:30px; bottom:0; border-radius:16px; border:1px solid; }
  .group .ghead { position:absolute; left:8px; top:0; height:30px; display:flex; align-items:center; gap:0; white-space:nowrap; }
  .group .ghead i { width:8px; height:8px; border-radius:50%; margin-right:8px; }
  .group .gname { font-size:13px; font-weight:700; letter-spacing:1px; }
  .group .gmeta { font:11px ui-monospace, Menlo, monospace; color:var(--dim); white-space:pre; }
  .group .gcol { position:absolute; left:18px; top:46px; font-size:12px; color:var(--dim); }
  .alabel { position:absolute; transform:translate(-50%, -50%); font-size:15px; background:var(--canvas); border-radius:5px; padding:1px 6px; white-space:nowrap; pointer-events:none; }

  /* 떠 있는 막대(앱의 위쪽 왼쪽·오른쪽, 아래 오른쪽) */
  .float { position:fixed; z-index:10; display:flex; align-items:center; gap:8px; }
  .cap { background:var(--surface); border:1px solid var(--border); border-radius:12px; box-shadow:0 4px 14px rgba(var(--shadow), .28); display:flex; align-items:center; }
  #tl { left:14px; top:12px; max-width:calc(100% - 28px); }
  #tl .cap { padding:4px; gap:4px; overflow-x:auto; max-width:100%; }
  .proj { display:flex; align-items:center; gap:6px; padding:0 10px 0 8px; font-size:12px; font-weight:500; white-space:nowrap; }
  .sep { width:1px; height:18px; background:var(--border); flex:none; }
  .wtab { display:flex; align-items:center; gap:6px; padding:5px 10px; border-radius:8px; border:1px solid transparent; font-size:12px; white-space:nowrap; cursor:pointer; flex:none; background:none; color:var(--text); font-family:inherit; }
  .wtab.on { font-weight:600; border-color:var(--accent); background:rgba(240,90,56,.10); }
  .wtab .n { font:700 10px ui-monospace, Menlo, monospace; color:var(--accent); }
  .wtab .here { width:5px; height:5px; border-radius:50%; background:var(--accent); opacity:.8; }
  #tr { right:14px; top:12px; }
  #tr .cap { padding:6px 11px; gap:6px; font-size:12px; white-space:nowrap; }
  #tr .live i { width:7px; height:7px; border-radius:50%; display:block; }
  #br { right:14px; bottom:14px; }
  #br .cap { padding:2px 4px; gap:0; }
  #br button { background:none; border:0; color:var(--text); width:30px; height:28px; font:inherit; font-size:15px; cursor:pointer; border-radius:8px; }
  #br button:hover { background:rgba(127,127,127,.15); }
  #br .pct { font:12px ui-monospace, Menlo, monospace; min-width:46px; text-align:center; color:var(--text); }
  #msg { position:fixed; inset:0; display:flex; align-items:center; justify-content:center; color:var(--dim); font-size:14px; pointer-events:none; z-index:5; }
  @media (max-width:640px) { #tr .vo { display:none; } }
</style>
</head>
<body>
<div id="viewport"><div id="world"></div></div>
<div id="msg">Connecting...</div>
<div class="float" id="tl"><div class="cap" id="tabs"></div></div>
<div class="float" id="tr">
  <div class="cap live"><i id="liveDot"></i><b id="liveN">0</b><span class="dim" style="color:var(--dim)">live</span><span id="working" style="color:var(--accent)"></span></div>
  <div class="cap vo" id="mode" style="color:var(--dim)">View only</div>
</div>
<div class="float" id="br"><div class="cap">
  <button id="zOut" title="Zoom out">&minus;</button><span class="pct" id="pct">100%</span><button id="zIn" title="Zoom in">+</button>
  <span class="sep" style="margin:0 2px"></span><button id="zFit" title="Zoom to fit">
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M2 6V2h4M10 2h4v4M14 10v4h-4M6 14H2v-4"/></svg></button>
</div></div>
<script>
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  var BASE = location.pathname.replace(/\/$/, '');
  var CONTROL = /^\/c\//.test(location.pathname);
  var viewport = document.getElementById('viewport');
  var world = document.getElementById('world');
  var msg = document.getElementById('msg');
  var tabsEl = document.getElementById('tabs');

  var boards = {};        // 작업공간 id → board
  var snap = null;        // 마지막 meta
  var info = {};          // 콘솔 id → meta 의 콘솔 정보
  var consoles = {};      // 콘솔 id → { el, term, box, chat, ... } (작업공간을 오가도 유지)
  var selected = null, follow = true;
  var views = {};         // 작업공간 id → {x, y, z}
  var view = { x: 0, y: 0, z: 1 };

  // ---------- 작은 도구 ----------
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function svg(tag, attrs) { var e = document.createElementNS(NS, tag); for (var k in attrs) e.setAttribute(k, attrs[k]); return e; }
  function hexA(hex, a) {
    var h = (hex || '#888888').replace('#', ''); if (h.length === 3) h = h.split('').map(function (c) { return c + c; }).join('');
    var n = parseInt(h.slice(0, 6), 16); return 'rgba(' + (n >> 16 & 255) + ',' + (n >> 8 & 255) + ',' + (n & 255) + ',' + a + ')';
  }
  function lum(hex) {
    var h = (hex || '#C9A227').replace('#', ''); var n = parseInt(h.slice(0, 6), 16);
    function c(v) { return v / 255; }
    return 0.2126 * c(n >> 16 & 255) + 0.7152 * c(n >> 8 & 255) + 0.0722 * c(n & 255);
  }
  // Theme.ink: 어두운 바탕용으로 저장된 글·선 색을 지금 모드 색으로.
  function ink(hex) {
    if (!hex) return null;
    switch (hex.toUpperCase()) { case '#ECE7E2': return 'var(--text)'; case '#8F8882': return 'var(--dim)'; case '#5A5550': return 'var(--ink3)'; default: return hex; }
  }
  function nodeFont(style, def) {
    var f = (style && style.font) || def || 'hand';
    if (f === 'sans') return '500 {s}px -apple-system, BlinkMacSystemFont, sans-serif';
    if (f === 'serif') return '400 {s}px "New York", Georgia, serif';
    if (f === 'mono') return '400 {s}px ui-monospace, Menlo, monospace';
    return '400 {s}px "Chalkboard SE", Noteworthy, "Marker Felt", "Comic Sans MS", cursive';
  }
  var ICONS = {
    checklist: 'M3 4.5l1.5 1.5L7 3.5M3 10.5l1.5 1.5L7 9.5M9.5 5h4M9.5 11h4',
    kanban: 'M2.5 2.5h3v11h-3zM6.5 2.5h3v7h-3zM10.5 2.5h3v9h-3z',
    calendar: 'M2.5 3.5h11v10h-11zM2.5 6.5h11M5.5 2v3M10.5 2v3',
    web: 'M8 2a6 6 0 100 12A6 6 0 008 2zM2 8h12M8 2c2 2 2 10 0 12M8 2c-2 2-2 10 0 12',
    git: 'M5 3v10M5 6a3 3 0 003 3h1M11 9a1.5 1.5 0 100 .01M5 3a1.5 1.5 0 100 .01M5 13a1.5 1.5 0 100 .01',
    orchestrator: 'M8 2.5v3M8 10.5v3M2.5 8h3M10.5 8h3M8 8a2.5 2.5 0 100 .01',
    file: 'M4 2.5h5l3 3v8H4zM9 2.5v3h3',
    document: 'M4 2.5h5l3 3v8H4zM6 8h4M6 10.5h4',
    memory: 'M3 4h10v8H3zM5.5 4v8M10.5 4v8',
    inspector: 'M7 3a4 4 0 100 8 4 4 0 000-8zM10 10l3.5 3.5',
    image: 'M2.5 3.5h11v9h-11zM2.5 10.5l3-3 3 3 2-2 3 3'
  };
  function kindIcon(kind) {
    var s = svg('svg', { viewBox: '0 0 16 16', fill: 'none', stroke: 'currentColor', 'stroke-width': '1.4', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', class: 'kicon' });
    s.appendChild(svg('path', { d: ICONS[kind] || 'M3 3h10v10H3z' }));
    return s;
  }

  // ---------- 보기(이동·확대) ----------
  function applyView() {
    world.style.transform = 'translate(' + view.x + 'px,' + view.y + 'px) scale(' + view.z + ')';
    var step = 36 * view.z;
    if (view.z > 0.25) {
      viewport.style.backgroundImage = 'radial-gradient(circle, var(--dot) ' + Math.max(0.6, view.z) + 'px, transparent ' + (Math.max(0.6, view.z) + 0.5) + 'px)';
      viewport.style.backgroundSize = step + 'px ' + step + 'px';
      viewport.style.backgroundPosition = (view.x - step / 2) + 'px ' + (view.y - step / 2) + 'px';
    } else viewport.style.backgroundImage = 'none';
    document.getElementById('pct').textContent = Math.round(view.z * 100) + '%';
    if (selected) views[selected] = { x: view.x, y: view.y, z: view.z };
  }
  function zoomAt(z, cx, cy) {
    z = Math.max(0.1, Math.min(3, z));
    var wx = (cx - view.x) / view.z, wy = (cy - view.y) / view.z;
    view.z = z; view.x = cx - wx * z; view.y = cy - wy * z;
    applyView();
  }
  function bounds(b) {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    b.nodes.forEach(function (n) { if (n.hidden) return; minX = Math.min(minX, n.x); minY = Math.min(minY, n.y); maxX = Math.max(maxX, n.x + n.w); maxY = Math.max(maxY, n.y + n.h); });
    b.groups.forEach(function (g) { minX = Math.min(minX, g.x); minY = Math.min(minY, g.y); maxX = Math.max(maxX, g.x + g.w); maxY = Math.max(maxY, g.y + g.h); });
    return isFinite(minX) ? { x: minX, y: minY, w: maxX - minX, h: maxY - minY } : null;
  }
  function fit() {
    var b = boards[selected]; if (!b) return;
    var r = bounds(b), W = innerWidth, H = innerHeight;
    if (!r) { view = { x: W / 2, y: H / 2, z: 1 }; applyView(); return; }
    var pad = 60, top = 56;
    var z = Math.max(0.1, Math.min(1, Math.min((W - pad * 2) / r.w, (H - top - pad * 2) / r.h)));
    view = { z: z, x: (W - r.w * z) / 2 - r.x * z, y: top + (H - top - r.h * z) / 2 - r.y * z };
    applyView();
  }
  // 처음 열면 맥에서 보던 자리(viewport)를, 화면이 좁으면 전체가 보이게.
  function initialView(b) {
    if (views[b.id]) { view = views[b.id]; applyView(); return; }
    if (innerWidth >= 1000 && b.viewport && b.viewport.zoom) {
      var z = b.viewport.zoom;
      view = { z: z, x: innerWidth / 2 - b.viewport.center.x * z, y: innerHeight / 2 - b.viewport.center.y * z };
      applyView();
      var r = bounds(b);
      // 저장된 자리에 아무것도 안 보이면 전체 보기.
      if (r && (r.x * z + view.x > innerWidth || (r.x + r.w) * z + view.x < 0 || r.y * z + view.y > innerHeight || (r.y + r.h) * z + view.y < 0)) fit();
    } else fit();
  }
  document.getElementById('zIn').onclick = function () { zoomAt(view.z * 1.25, innerWidth / 2, innerHeight / 2); };
  document.getElementById('zOut').onclick = function () { zoomAt(view.z / 1.25, innerWidth / 2, innerHeight / 2); };
  document.getElementById('zFit').onclick = fit;

  function scrollable(t) { return t && t.closest && t.closest('.chat, .xterm-viewport, .xterm-screen, .compose'); }
  function consoleAt(t) {
    var n = t && t.closest && t.closest('.node.term');
    if (!n) return null;
    for (var id in consoles) if (consoles[id].node === n) return consoles[id];
    return null;
  }
  viewport.addEventListener('wheel', function (e) {
    if (!e.ctrlKey && scrollable(e.target)) {
      // 전체 화면 프로그램(claude)을 터미널 화면으로 볼 때는 지난 줄이 없어 휠이 아무 일도 하지 않았다.
      // 대화 보기가 있으면 그리로 바꿔 스크롤하고, 없으면 보드를 움직인다. 입력이 허용된 콘솔은 xterm 이 휠을 프로그램에 넘긴다.
      var c = consoleAt(e.target);
      if (!c || c.mode !== 'screen' || c.canType || c.term.buffer.active.type !== 'alternate') return;   // 대화·터미널 안은 그 안을 스크롤
      if (info[c.id] && info[c.id].chat) {
        e.preventDefault(); e.stopPropagation();
        setMode(c, 'chat');
        c.chat.scrollTop += e.deltaY;
        return;
      }
    }
    e.preventDefault();
    if (e.ctrlKey) zoomAt(view.z * Math.exp(-e.deltaY * 0.01), e.clientX, e.clientY);
    else { view.x -= e.deltaX; view.y -= e.deltaY; applyView(); }
    e.stopPropagation();
  }, { passive: false, capture: true });   // xterm 이 휠을 받아 전파를 끊기 전에 먼저 본다
  // 끌어서 이동, 두 손가락으로 확대(대화 안에서 시작한 끌기는 대화 스크롤).
  var pointers = {}, pinch = null, drag = null;
  viewport.addEventListener('pointerdown', function (e) {
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    if (scrollable(e.target) || (e.target.closest && e.target.closest('button'))) return;
    pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
    viewport.setPointerCapture(e.pointerId);
    var ids = Object.keys(pointers);
    if (ids.length === 2) {
      var a = pointers[ids[0]], b = pointers[ids[1]];
      pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), z: view.z }; drag = null;
    } else { drag = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y }; viewport.classList.add('panning'); }
  });
  viewport.addEventListener('pointermove', function (e) {
    if (!pointers[e.pointerId]) return;
    pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
    var ids = Object.keys(pointers);
    if (pinch && ids.length >= 2) {
      var a = pointers[ids[0]], b = pointers[ids[1]];
      zoomAt(pinch.z * Math.hypot(a.x - b.x, a.y - b.y) / pinch.d, (a.x + b.x) / 2, (a.y + b.y) / 2);
    } else if (drag) { view.x = drag.vx + e.clientX - drag.x; view.y = drag.vy + e.clientY - drag.y; applyView(); }
  });
  function up(e) {
    delete pointers[e.pointerId];
    if (Object.keys(pointers).length < 2) pinch = null;
    if (!Object.keys(pointers).length) { drag = null; viewport.classList.remove('panning'); }
  }
  viewport.addEventListener('pointerup', up); viewport.addEventListener('pointercancel', up);
  addEventListener('resize', function () { Object.keys(consoles).forEach(function (id) { fitTerm(consoles[id]); }); });

  // ---------- 콘솔 ----------
  var I_CHAT = 'M3 3.5h10v7H7l-3 2.5v-2.5H3z', I_TERM = 'M2.5 3.5h11v9h-11zM5 7l2 1.5L5 10M8.5 10.5H11';
  function iconBtn(d, tip) {
    var b = el('button', 'hbtn'); b.title = tip;
    var s = svg('svg', { width: 13, height: 13, viewBox: '0 0 16 16', fill: 'none', stroke: 'currentColor', 'stroke-width': '1.6', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
    s.appendChild(svg('path', { d: d })); b.appendChild(s); return b;
  }
  function consoleFor(id) {
    var c = consoles[id]; if (c) return c;
    var node = el('div', 'node term');
    var head = el('div', 'nhead');
    var glyph = el('div', 'glyph');
    var chev = el('div', 'chev'); chev.innerHTML = '<svg width="8" height="8" viewBox="0 0 8 8"><path d="M1.5 3l2.5 2.5L6.5 3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>';
    var dot = el('div', 'sdot'), title = el('div', 'ntitle'), role = el('div', 'nrole'), pill = el('div', 'pill');
    var bChat = iconBtn(I_CHAT, 'Conversation'), bTerm = iconBtn(I_TERM, 'Screen');
    var badge = el('div', 'typing-badge', 'CAN TYPE');
    head.append(glyph, chev, dot, title, role, badge, pill, bChat, bTerm);
    var body = el('div', 'nbody'), box = el('div', 'tbox'), chat = el('div', 'chat');
    var compose = el('div', 'compose'), field = el('textarea'), sendB = el('button', '', 'Send');
    field.placeholder = 'Message - Enter to send, Shift+Enter for a new line';
    compose.append(field, sendB);
    var lockbar = el('div', 'lockbar');
    lockbar.innerHTML = '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="3" y="7" width="10" height="7" rx="1.5"/><path d="M5.5 7V5a2.5 2.5 0 015 0v2"/></svg>';
    lockbar.appendChild(el('span', '', 'Typing is off for this console. On the Mac, turn on "Allow typing" for it in the share window.'));
    chat.appendChild(el('div', 'none', 'Loading the conversation...'));
    var jump = el('button', 'jump', 'Jump to latest'); jump.style.display = 'none';
    body.append(box, chat, compose, lockbar); node.append(head, body);
    var term = new Terminal({ disableStdin: true, cursorBlink: false, scrollback: 5000, fontSize: 12, lineHeight: 1,
      fontFamily: 'ui-monospace, "SF Mono", Menlo, Monaco, monospace',
      theme: { background: '#121110', foreground: '#ECE7E2', cursor: '#ECE7E2' } });
    c = { id: id, node: node, head: head, glyph: glyph, dot: dot, title: title, role: role, pill: pill, bChat: bChat, bTerm: bTerm,
          box: box, chat: chat, jump: jump, term: term, opened: false, cols: 80, rows: 24, mode: null, hasChat: false, w: 0, h: 0,
          field: field, canType: false };
    // 조작 링크: 터미널에 친 글자는 모아서 짧은 간격으로 보낸다.
    var pendingKeys = '', keyTimer = null;
    term.onData(function (d) {
      if (!c.canType) return;
      pendingKeys += d;
      if (!keyTimer) keyTimer = setTimeout(function () { var k = pendingKeys; pendingKeys = ''; keyTimer = null; post({ id: id, keys: k }); }, 25);
    });
    function submit() {
      var t = field.value; if (!t.trim() || !c.canType) return;
      field.value = ''; post({ id: id, text: t, submit: true });
    }
    sendB.onclick = submit;
    field.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.keyCode !== 229) { e.preventDefault(); submit(); }
    });
    bChat.onclick = function () { setMode(c, 'chat'); };
    bTerm.onclick = function () { setMode(c, 'screen'); };
    jump.onclick = function () { chat.scrollTop = chat.scrollHeight; };
    chat.addEventListener('scroll', function () { jump.style.display = nearBottom(chat) ? 'none' : ''; });
    consoles[id] = c;
    return c;
  }
  function nearBottom(e) { return e.scrollHeight - e.scrollTop - e.clientHeight < 40; }
  function setMode(c, mode) {
    c.mode = mode;
    c.box.style.visibility = mode === 'screen' ? '' : 'hidden';
    c.chat.style.display = mode === 'chat' ? '' : 'none';
    c.bChat.classList.toggle('on', mode === 'chat'); c.bTerm.classList.toggle('on', mode === 'screen');
    c.node.classList.toggle('chatmode', mode === 'chat');
    if (mode === 'chat') c.chat.scrollTop = c.chat.scrollHeight; else fitTerm(c);
  }
  // 맥 콘솔과 같은 칸 수·줄 수가 노드 몸통에 꼭 맞도록 글자 크기를 정한다.
  function fitTerm(c) {
    if (!c.opened || !c.w) return;
    var w = c.w - 12, h = c.h - 28 - 8;
    var size = Math.max(3, Math.min(24, Math.min(w / (c.cols * 0.602), h / (c.rows * 1.18))));
    size = Math.floor(size * 10) / 10;
    if (c.term.options.fontSize !== size) c.term.options.fontSize = size;
  }
  function updateConsole(c, ci, n) {
    c.title.textContent = n ? n.title : ci.name;
    c.role.textContent = (n && n.role) || '';
    var gh = (n && n.glyphHex) || '#9A938C';
    c.glyph.textContent = (n && n.glyph) || '>_';
    c.glyph.style.background = hexA(gh, .18); c.glyph.style.border = '1px solid ' + hexA(gh, .55); c.glyph.style.color = gh;
    c.glyph.style.fontSize = c.glyph.textContent.length > 1 ? '7.5px' : '10px';
    if (ci) {
      c.dot.style.display = ''; c.pill.style.display = '';
      c.dot.style.background = ci.pillHex;
      c.pill.innerHTML = ''; var d = el('i'); d.style.background = ci.pillHex; c.pill.append(d, document.createTextNode(ci.pill));
      c.pill.style.color = ci.pillHex; c.pill.style.background = hexA(ci.pillHex, .10); c.pill.style.border = '1px solid ' + hexA(ci.pillHex, .35);
      c.node.classList.toggle('waiting', ci.status === 'waiting');
      c.canType = CONTROL && !!ci.input;
      c.node.classList.toggle('typing', c.canType);
      c.node.classList.toggle('locked', CONTROL && !c.canType);
      if (c.term.options.disableStdin === c.canType) c.term.options.disableStdin = !c.canType;
      c.bChat.style.display = ci.chat ? '' : 'none'; c.bTerm.style.display = ci.chat ? '' : 'none';
      if (c.mode === null) setMode(c, ci.chat ? 'chat' : 'screen');
      else if (!ci.chat && c.mode === 'chat') setMode(c, 'screen');
      if (c.cols !== ci.cols || c.rows !== ci.rows) { c.cols = ci.cols; c.rows = ci.rows; c.term.resize(ci.cols, ci.rows); fitTerm(c); }
    } else { c.dot.style.display = 'none'; c.pill.style.display = 'none'; if (c.mode === null) setMode(c, 'screen'); }
  }
  function addEntries(c, entries, reset) {
    var stick = reset || nearBottom(c.chat);
    if (reset || !c.hasChat) { c.chat.textContent = ''; c.chat.appendChild(c.jump); }
    c.hasChat = true;
    entries.forEach(function (e) { c.chat.insertBefore(el('div', 'msg ' + e.role, e.text), c.jump); });
    if (!c.chat.querySelector('.msg')) c.chat.insertBefore(el('div', 'none', 'No messages yet.'), c.jump);
    if (stick) c.chat.scrollTop = c.chat.scrollHeight;
    c.jump.style.display = nearBottom(c.chat) ? 'none' : '';
  }

  // ---------- 다른 노드 ----------
  function header(n) {
    var h = el('div', 'nhead'); h.appendChild(kindIcon(n.kind));
    h.appendChild(el('div', 'ntitle', n.title)); if (n.role) h.appendChild(el('div', 'nrole', n.role));
    return h;
  }
  function placeholder(text) { var p = el('div', 'ph'); p.appendChild(el('div', '', text)); return p; }

  function stickyNode(n) {
    var w = n.w, h = n.h, fold = 22, pw = w - 6, ph = h - 8, paper = n.colorHex || '#C9A227';
    var wrap = el('div', 'sticky');
    var s = svg('svg', { width: w, height: h, style: 'position:absolute;left:0;top:0;overflow:visible' });
    var id = 'g' + n.id.replace(/-/g, '');
    var defs = svg('defs', {}), grad = svg('linearGradient', { id: id, x1: 0, y1: 0, x2: 0, y2: 1 });
    grad.append(svg('stop', { offset: 0, 'stop-color': paper, 'stop-opacity': .92 }), svg('stop', { offset: 1, 'stop-color': paper }));
    var clip = svg('clipPath', { id: id + 'c' });
    var d = 'M4 0L' + (pw - 4) + ' 0Q' + pw + ' 0 ' + pw + ' 4L' + pw + ' ' + (ph - fold) + 'L' + (pw - fold) + ' ' + ph + 'L4 ' + ph + 'Q0 ' + ph + ' 0 ' + (ph - 4) + 'L0 4Q0 0 4 0Z';
    clip.appendChild(svg('path', { d: d }));
    defs.append(grad, clip); s.appendChild(defs);
    s.appendChild(svg('path', { d: d, fill: 'url(#' + id + ')', style: 'filter:drop-shadow(0 4px 6px rgba(0,0,0,.45))' }));
    var lines = ''; for (var y = 34; y < h - 8; y += 24) lines += 'M10 ' + y + 'L' + (w - 14) + ' ' + y;
    if (lines) s.appendChild(svg('path', { d: lines, stroke: 'rgba(255,255,255,.12)', 'stroke-width': 1, 'clip-path': 'url(#' + id + 'c)' }));
    s.appendChild(svg('path', { d: 'M' + (pw - fold) + ' ' + ph + 'L' + (pw - fold) + ' ' + (ph - fold) + 'L' + pw + ' ' + (ph - fold) + 'Z', fill: 'rgba(0,0,0,.28)' }));
    var t = el('div', 'txt hand', n.text || '');
    t.style.width = pw + 'px'; t.style.height = ph + 'px';
    t.style.color = lum(paper) > 0.7 ? '#2A2117' : '#FFF8EC';
    wrap.append(s, t);
    return wrap;
  }

  function textNode(n) {
    var st = n.style || {};
    var t = el('div', 'textnode');
    var size = st.fontSize || 28;
    t.style.font = nodeFont(st, 'hand').replace('{s}', size);
    t.style.lineHeight = '1.2';
    t.style.color = ink(st.textColorHex) || 'var(--text)';
    t.style.textAlign = st.align === 'center' ? 'center' : (st.align === 'right' ? 'right' : 'left');
    t.style.opacity = st.opacity == null ? 1 : st.opacity;
    if (n.text) t.textContent = n.text; else { t.textContent = 'Type something'; t.classList.add('placeholder'); }
    t.style.width = '100%'; t.style.height = '100%';
    return t;
  }

  // ShapeNode.RoughPen 을 그대로 옮긴 것(같은 씨앗이면 같은 손그림 선).
  function RoughPen(seed, roughness) { this.s = seed; this.r = roughness; }
  RoughPen.prototype.next = function () {
    this.s = (this.s * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn;
    return Number((this.s >> 33n) & 0xFFFFn) / 65535 - 0.5;
  };
  RoughPen.prototype.line = function (a, b, out) {
    var len = Math.hypot(b[0] - a[0], b[1] - a[1]);
    var r = this.r * Math.min(2.5, len / 60 + 0.6), self = this;
    function j(v) { return v * r * 2; }
    var s = [a[0] + j(self.next()), a[1] + j(self.next())];
    var e = [b[0] + j(self.next()), b[1] + j(self.next())];
    var m = [(s[0] + e[0]) / 2 + j(self.next()) * 1.6, (s[1] + e[1]) / 2 + j(self.next()) * 1.6];
    out.push('M' + s[0] + ' ' + s[1] + 'Q' + m[0] + ' ' + m[1] + ' ' + e[0] + ' ' + e[1]);
  };
  RoughPen.prototype.polygon = function (pts) {
    var out = [];
    if (this.r === 0) return 'M' + pts.map(function (p) { return p[0] + ' ' + p[1]; }).join('L') + 'Z';
    for (var pass = 0; pass < 2; pass++) for (var i = 0; i < pts.length; i++) this.line(pts[i], pts[(i + 1) % pts.length], out);
    return out.join('');
  };
  RoughPen.prototype.ellipse = function (x, y, w, h) {
    var cx = x + w / 2, cy = y + h / 2;
    if (this.r === 0) return 'M' + (cx + w / 2) + ' ' + cy + 'A' + w / 2 + ' ' + h / 2 + ' 0 1 1 ' + (cx - w / 2) + ' ' + cy + 'A' + w / 2 + ' ' + h / 2 + ' 0 1 1 ' + (cx + w / 2) + ' ' + cy;
    var out = '';
    for (var pass = 0; pass < 2; pass++) {
      var n = 28, k = this.r * 3;
      for (var i = 0; i <= n; i++) {
        var t = i / n * 2 * Math.PI + pass * 0.3;
        var dx = this.next() * k, dy = this.next() * k;
        out += (i ? 'L' : 'M') + (cx + (w / 2 + dx) * Math.cos(t)) + ' ' + (cy + (h / 2 + dy) * Math.sin(t));
      }
    }
    return out;
  };
  function seedOf(uuid) {
    var h = 1469598103934665603n;
    for (var i = 0; i < uuid.length; i++) h = ((h ^ BigInt(uuid.charCodeAt(i))) * 1099511628211n) & 0xFFFFFFFFFFFFFFFFn;
    return h;
  }
  function shapeNode(n) {
    var sp = n.shape || { kind: 'rect', strokeHex: '#ECE7E2', strokeWidth: 2, dash: 'solid', roughness: 1, cornerRadius: 10 };
    var st = n.style || { fontSize: 20, font: 'hand', align: 'center' };
    var wrap = el('div'); wrap.style.position = 'absolute'; wrap.style.inset = '0'; wrap.style.opacity = st.opacity == null ? 1 : st.opacity;
    var inset = sp.strokeWidth + 4, x = inset, y = inset, w = n.w - inset * 2, h = n.h - inset * 2;
    var s = svg('svg', { width: n.w, height: n.h, style: 'position:absolute;left:0;top:0;overflow:visible' });
    if (sp.fillHex && sp.kind !== 'arrow') {
      var fd;
      if (sp.kind === 'ellipse') fd = 'M' + (x + w) + ' ' + (y + h / 2) + 'A' + w / 2 + ' ' + h / 2 + ' 0 1 1 ' + x + ' ' + (y + h / 2) + 'A' + w / 2 + ' ' + h / 2 + ' 0 1 1 ' + (x + w) + ' ' + (y + h / 2);
      else if (sp.kind === 'diamond') fd = 'M' + (x + w / 2) + ' ' + y + 'L' + (x + w) + ' ' + (y + h / 2) + 'L' + (x + w / 2) + ' ' + (y + h) + 'L' + x + ' ' + (y + h / 2) + 'Z';
      else { var cr = Math.min(sp.cornerRadius || 0, w / 2, h / 2); fd = 'M' + (x + cr) + ' ' + y + 'H' + (x + w - cr) + 'Q' + (x + w) + ' ' + y + ' ' + (x + w) + ' ' + (y + cr) + 'V' + (y + h - cr) + 'Q' + (x + w) + ' ' + (y + h) + ' ' + (x + w - cr) + ' ' + (y + h) + 'H' + (x + cr) + 'Q' + x + ' ' + (y + h) + ' ' + x + ' ' + (y + h - cr) + 'V' + (y + cr) + 'Q' + x + ' ' + y + ' ' + (x + cr) + ' ' + y + 'Z'; }
      s.appendChild(svg('path', { d: fd, fill: sp.fillHex, 'fill-opacity': .85 }));
    }
    var pen = new RoughPen(seedOf(n.id), sp.roughness), d;
    if (sp.kind === 'ellipse') d = pen.ellipse(x, y, w, h);
    else if (sp.kind === 'diamond') d = pen.polygon([[x + w / 2, y], [x + w, y + h / 2], [x + w / 2, y + h], [x, y + h / 2]]);
    else if (sp.kind === 'arrow') {
      var out = [], my = y + h / 2, head = Math.min(18, w / 4);
      pen.line([x, my], [x + w, my], out); pen.line([x + w, my], [x + w - head, my - head * 0.6], out); pen.line([x + w, my], [x + w - head, my + head * 0.6], out);
      d = out.join('');
    } else if (sp.roughness === 0) {
      var r0 = sp.cornerRadius || 0; d = 'M' + (x + r0) + ' ' + y + 'H' + (x + w - r0) + 'Q' + (x + w) + ' ' + y + ' ' + (x + w) + ' ' + (y + r0) + 'V' + (y + h - r0) + 'Q' + (x + w) + ' ' + (y + h) + ' ' + (x + w - r0) + ' ' + (y + h) + 'H' + (x + r0) + 'Q' + x + ' ' + (y + h) + ' ' + x + ' ' + (y + h - r0) + 'V' + (y + r0) + 'Q' + x + ' ' + y + ' ' + (x + r0) + ' ' + y + 'Z';
    } else {
      var c = Math.min(sp.cornerRadius || 0, Math.min(w, h) / 3);
      d = pen.polygon(c > 2 ? [[x + c, y], [x + w - c, y], [x + w, y + c], [x + w, y + h - c], [x + w - c, y + h], [x + c, y + h], [x, y + h - c], [x, y + c]]
                            : [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
    }
    var dash = sp.dash === 'dashed' ? (sp.strokeWidth * 4) + ' ' + (sp.strokeWidth * 3) : (sp.dash === 'dotted' ? '1 ' + (sp.strokeWidth * 2.5) : '');
    var attrs = { d: d, fill: 'none', stroke: ink(sp.strokeHex) || 'var(--text)', 'stroke-width': sp.strokeWidth, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' };
    if (dash) attrs['stroke-dasharray'] = dash;
    s.appendChild(svg('path', attrs));
    wrap.appendChild(s);
    if (sp.kind !== 'arrow' && n.text) {
      var t = el('div', '', n.text), fs = st.fontSize || 20;
      t.style.cssText = 'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);white-space:pre-wrap;word-break:break-word;line-height:1.4;';
      t.style.width = (n.w * (sp.kind === 'rect' ? 0.86 : 0.68)) + 'px';
      t.style.font = nodeFont(st, 'hand').replace('{s}', fs); t.style.lineHeight = '1.4';
      t.style.textAlign = st.align === 'left' ? 'left' : (st.align === 'right' ? 'right' : 'center');
      t.style.color = ink(st.textColorHex) || 'var(--text)';
      wrap.appendChild(t);
    }
    return wrap;
  }

  function checklistBody(n) {
    var items = n.checklist || [], done = items.filter(function (i) { return i.done; }).length;
    var b = el('div'); b.style.cssText = 'position:absolute;inset:0;background:var(--surface)';
    var head = el('div', 'ck-head'), ring = el('div', 'ck-ring');
    var C = 2 * Math.PI * 13.5, frac = items.length ? done / items.length : 0;
    ring.innerHTML = '<svg width="30" height="30" viewBox="0 0 30 30"><circle cx="15" cy="15" r="13.5" fill="none" stroke="var(--border)" stroke-width="3"/>' +
      '<circle cx="15" cy="15" r="13.5" fill="none" stroke="var(--accent)" stroke-width="3" stroke-linecap="round" stroke-dasharray="' + (C * frac) + ' ' + C + '" transform="rotate(-90 15 15)"/></svg>';
    ring.appendChild(el('span', '', String(items.length - done)));
    var txt = el('div');
    txt.appendChild(el('div', '', items.length ? done + ' of ' + items.length + ' done' : 'No objectives')).style.cssText = 'font-size:13px;font-weight:600';
    txt.appendChild(el('div', '', items.length ? (done === items.length ? 'All clear' : (items.length - done) + ' left') : 'Add one to begin')).style.cssText = 'font-size:11px;color:var(--dim)';
    head.append(ring, txt); b.appendChild(head);
    var list = el('div', 'ck-items');
    items.forEach(function (it) {
      var row = el('div', 'ck-item' + (it.done ? ' done' : ''));
      row.innerHTML = it.done
        ? '<svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7.5" fill="var(--accent)"/><path d="M4.8 8.2l2.1 2.1 4.3-4.6" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>'
        : '<svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="none" stroke="var(--dim)" stroke-width="1.3"/></svg>';
      row.appendChild(el('span', '', it.text)); list.appendChild(row);
    });
    b.appendChild(list);
    return b;
  }

  function colColor(i, title) {
    switch ((title || '').toLowerCase()) { case 'to do': case 'todo': return '#56A8F5'; case 'in progress': case 'doing': return '#E9C46A'; case 'done': return '#6FCF97'; }
    return ['#B48CF2', '#F28AB2', '#56C2C9'][i % 3];
  }
  function prioColor(p) { return p === 'high' ? '#E8564A' : p === 'med' ? '#E9C46A' : p === 'low' ? '#6FCF97' : 'var(--dim)'; }
  function kanbanBody(n) {
    var kb = el('div', 'kb');
    (n.kanban || []).forEach(function (col, i) {
      var c = el('div', 'kb-col'), h = el('div', 'kb-h'), dot = el('i');
      dot.style.background = colColor(i, col.title);
      h.append(dot, el('span', '', col.title.toUpperCase()), el('small', '', String(col.cards.length)));
      c.appendChild(h);
      if (!col.cards.length) c.appendChild(el('div', 'kb-empty', 'No cards'));
      col.cards.forEach(function (cd) {
        var card = el('div', 'kb-card' + (cd.done ? ' done' : '')), bar = el('b');
        bar.style.background = prioColor(cd.priority); bar.style.opacity = cd.priority ? .9 : .3;
        card.append(bar, document.createTextNode(cd.title));
        if (cd.due) card.appendChild(el('small', '', new Date(cd.due).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })));
        c.appendChild(card);
      });
      kb.appendChild(c);
    });
    return kb;
  }

  function calendarBody(n) {
    var now = new Date(), y = now.getFullYear(), m = now.getMonth();
    var box = el('div', 'cal'); box.style.background = 'var(--surface)';
    box.appendChild(el('div', 'cal-h', now.toLocaleDateString(undefined, { year: 'numeric', month: 'long' })));
    var g = el('div', 'cal-g');
    ['S', 'M', 'T', 'W', 'T', 'F', 'S'].forEach(function (d) { g.appendChild(el('div', 'cal-w', d)); });
    var first = new Date(y, m, 1), start = new Date(y, m, 1 - first.getDay());
    var events = (n.events || []).map(function (e) { var d = new Date(e.day); return { k: d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate(), e: e }; });
    for (var i = 0; i < 42; i++) {
      var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
      var cell = el('div', 'cal-d' + (d.getMonth() !== m ? ' out' : '') + (d.toDateString() === now.toDateString() ? ' today' : ''));
      cell.appendChild(el('b', '', String(d.getDate())));
      var key = d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate();
      events.filter(function (x) { return x.k === key; }).forEach(function (x) {
        var ev = el('div', 'cal-e', x.e.title); ev.style.background = x.e.colorHex || 'var(--accent)'; cell.appendChild(ev);
      });
      g.appendChild(cell);
    }
    box.appendChild(g);
    return box;
  }

  function otherBody(n) {
    var b = el('div'); b.style.cssText = 'position:absolute;inset:0;background:var(--surface)';
    if (n.kind === 'web') {
      b.appendChild(el('div', 'web-bar', n.url || 'about:blank'));
      var p = placeholder('Web pages are not shared'); p.style.top = '44px'; b.appendChild(p);
    } else if (n.kind === 'image') {
      b.className = 'imgnode'; b.style.background = 'transparent';
      var img = el('img'); img.src = BASE + '/img/' + n.id; img.alt = ''; b.appendChild(img);
    } else if (n.kind === 'checklist') return checklistBody(n);
    else if (n.kind === 'kanban') return kanbanBody(n);
    else if (n.kind === 'calendar') return calendarBody(n);
    else {
      var names = { orchestrator: 'Orchestrator', git: 'Git', file: 'Code', document: 'Document', memory: 'Memory', inspector: 'Inspector' };
      b.appendChild(placeholder((names[n.kind] || n.kind) + ' - not shared in the view-only link'));
    }
    return b;
  }

  // ---------- 선·그룹·획 ----------
  // LinksView.path(from:to:) 와 같은 곡선.
  function linkPath(a, b) {
    var amx = a.x + a.w / 2, amy = a.y + a.h / 2, bmx = b.x + b.w / 2, bmy = b.y + b.h / 2, dx = bmx - amx, dy = bmy - amy, s, e, k;
    if (Math.abs(dx) >= Math.abs(dy)) {
      s = [dx >= 0 ? a.x + a.w : a.x, amy]; e = [dx >= 0 ? b.x : b.x + b.w, bmy];
      k = Math.max(Math.abs(e[0] - s[0]) * 0.5, 40) * (dx >= 0 ? 1 : -1);
      return 'M' + s[0] + ' ' + s[1] + 'C' + (s[0] + k) + ' ' + s[1] + ' ' + (e[0] - k) + ' ' + e[1] + ' ' + e[0] + ' ' + e[1];
    }
    s = [amx, dy >= 0 ? a.y + a.h : a.y]; e = [bmx, dy >= 0 ? b.y : b.y + b.h];
    k = Math.max(Math.abs(e[1] - s[1]) * 0.5, 40) * (dy >= 0 ? 1 : -1);
    return 'M' + s[0] + ' ' + s[1] + 'C' + s[0] + ' ' + (s[1] + k) + ' ' + e[0] + ' ' + (e[1] - k) + ' ' + e[0] + ' ' + e[1];
  }
  // LinksView.arrowPath: 꺾이는 점을 둥근 모서리로 잇고 끝에 화살촉.
  function arrowPath(pts) {
    if (pts.length < 2) return '';
    var d = 'M' + pts[0].x + ' ' + pts[0].y;
    for (var i = 1; i < pts.length - 1; i++) {
      var p = pts[i - 1], c = pts[i], n = pts[i + 1];
      var l1 = Math.hypot(c.x - p.x, c.y - p.y), l2 = Math.hypot(n.x - c.x, n.y - c.y), r = Math.min(14, l1 / 2, l2 / 2);
      var a = [c.x - (c.x - p.x) / (l1 || 1) * r, c.y - (c.y - p.y) / (l1 || 1) * r], b = [c.x + (n.x - c.x) / (l2 || 1) * r, c.y + (n.y - c.y) / (l2 || 1) * r];
      d += 'L' + a[0] + ' ' + a[1] + 'Q' + c.x + ' ' + c.y + ' ' + b[0] + ' ' + b[1];
    }
    var e = pts[pts.length - 1], f = pts[pts.length - 2], ang = Math.atan2(e.y - f.y, e.x - f.x);
    d += 'L' + e.x + ' ' + e.y;
    [Math.PI * 0.8, -Math.PI * 0.8].forEach(function (k) { d += 'M' + e.x + ' ' + e.y + 'L' + (e.x + 12 * Math.cos(ang + k)) + ' ' + (e.y + 12 * Math.sin(ang + k)); });
    return d;
  }
  function groupSummary(g) {
    var run = 0, wait = 0, done = 0;
    g.members.forEach(function (id) { var s = info[id] && info[id].status; if (s === 'working') run++; else if (s === 'waiting') wait++; else if (s === 'done') done++; });
    var parts = [];
    if (run) parts.push(run + ' running'); if (wait) parts.push(wait + ' need' + (wait === 1 ? 's' : '') + ' you'); if (done) parts.push(done + ' done');
    return parts.length ? parts.join(' · ') : 'idle';
  }

  // ---------- 그리기 ----------
  var groupEls = {};
  function render() {
    var b = boards[selected];
    // 다시 그리는 동안 콘솔 노드가 잠깐 빠져도 입력 중이던 칸의 포커스와 커서를 지킨다.
    var act = document.activeElement, keep = act && act.closest && act.closest('.node.term') ? act : null;
    var sel = keep && keep.tagName === 'TEXTAREA' ? [keep.selectionStart, keep.selectionEnd] : null;
    world.textContent = ''; groupEls = {};
    if (!b) return;
    // 1. 펜 획과 연결선(가장 아래)
    var under = svg('svg', { class: 'layer' });
    (b.strokes || []).forEach(function (s) {
      if (!s.points.length) return;
      var d = 'M' + s.points.map(function (p) { return p.x + ' ' + p.y; }).join('L');
      if (s.points.length === 1) d += 'L' + (s.points[0].x + 0.1) + ' ' + s.points[0].y;
      under.appendChild(svg('path', { d: d, fill: 'none', stroke: ink(s.colorHex) || s.colorHex, 'stroke-width': s.width, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }));
    });
    var defs = svg('defs', {}), glow = svg('filter', { id: 'glow', x: '-200%', y: '-200%', width: '500%', height: '500%' });
    glow.appendChild(svg('feGaussianBlur', { stdDeviation: 2.5 })); defs.appendChild(glow); under.appendChild(defs);
    b.links.forEach(function (l) {
      var d = linkPath(l.a, l.b);
      under.appendChild(svg('path', { d: d, fill: 'none', stroke: 'var(--accent)', 'stroke-opacity': l.faint ? .22 : .55, 'stroke-width': 2.5 }));
      var len = Math.hypot((l.b.x + l.b.w / 2) - (l.a.x + l.a.w / 2), (l.b.y + l.b.h / 2) - (l.a.y + l.a.h / 2));
      var dur = Math.max(1.6, len / 140) + 's';
      [['glow', .9], [null, l.faint ? .45 : 1]].forEach(function (k) {
        var c = svg('circle', { r: 3.5, fill: 'var(--accent)', 'fill-opacity': k[1] });
        if (k[0]) c.setAttribute('filter', 'url(#glow)');
        var m = svg('animateMotion', { dur: dur, repeatCount: 'indefinite', path: d, calcMode: 'paced' });
        c.appendChild(m); under.appendChild(c);
      });
    });
    world.appendChild(under);
    // 2. 그룹 프레임
    b.groups.forEach(function (g) {
      var e = el('div', 'group'); e.style.left = g.x + 'px'; e.style.top = g.y + 'px'; e.style.width = g.w + 'px'; e.style.height = g.h + 'px';
      var body = el('div', 'gbody'); body.style.borderColor = hexA(g.colorHex, .45); body.style.background = hexA(g.colorHex, .035);
      var head = el('div', 'ghead'), dot = el('i'); dot.style.background = g.colorHex;
      var meta = el('span', 'gmeta');
      head.append(dot, el('span', 'gname', g.name.toUpperCase()), meta);
      var chev = el('span'); chev.innerHTML = '<svg width="10" height="10" viewBox="0 0 10 10" style="margin-left:10px;color:var(--dim)"><path d="' + (g.collapsed ? 'M3.5 2l3 3-3 3' : 'M2 3.5l3 3 3-3') + '" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';
      head.appendChild(chev);
      e.append(body, head);
      if (g.collapsed) e.appendChild(el('div', 'gcol', g.count + ' hidden'));
      world.appendChild(e);
      groupEls[g.id] = { g: g, meta: meta };
    });
    updateGroups();
    // 3. 노드(배열 순서가 겹침 순서). 다이어그램 화살표는 가장 위 납작한 노드 바로 위.
    var topFlat = -2;
    b.nodes.forEach(function (n, i) { if (['text', 'sticky', 'image', 'shape'].indexOf(n.kind) >= 0) topFlat = i * 2; });
    b.nodes.forEach(function (n, i) {
      if (n.hidden) return;
      var e;
      if (n.kind === 'terminal') {
        var c = consoleFor(n.id);
        e = c.node; c.w = n.w; c.h = n.h;
        updateConsole(c, info[n.id], n);
      } else if (['text', 'sticky', 'image', 'shape'].indexOf(n.kind) >= 0) {
        e = el('div', 'node flat');
        var inner = n.kind === 'sticky' ? stickyNode(n) : n.kind === 'text' ? textNode(n) : n.kind === 'shape' ? shapeNode(n) : otherBody(n);
        e.appendChild(inner);
      } else {
        e = el('div', 'node');
        var body = el('div', 'nbody'); body.appendChild(otherBody(n));
        e.append(header(n), body);
      }
      e.style.left = n.x + 'px'; e.style.top = n.y + 'px'; e.style.width = n.w + 'px'; e.style.height = n.h + 'px'; e.style.zIndex = i * 2 + 10;
      world.appendChild(e);
      if (n.kind === 'terminal') {
        var cc = consoles[n.id];
        if (!cc.opened) { cc.term.open(cc.box); cc.opened = true; }
        fitTerm(cc);
      }
    });
    // 4. 다이어그램 화살표
    if (b.arrows.length) {
      var top = svg('svg', { class: 'layer', style: 'z-index:' + (topFlat + 11) });
      b.arrows.forEach(function (a) {
        top.appendChild(svg('path', { d: arrowPath(a.points), fill: 'none', stroke: ink(a.colorHex) || 'var(--text)', 'stroke-width': 2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }));
      });
      world.appendChild(top);
      b.arrows.forEach(function (a) {
        if (!a.label) return;
        var t = el('div', 'alabel hand', a.label); t.style.left = a.labelAt.x + 'px'; t.style.top = a.labelAt.y + 'px'; t.style.zIndex = topFlat + 12;
        world.appendChild(t);
      });
    }
    msg.style.display = b.nodes.length ? 'none' : '';
    msg.textContent = 'This workspace is empty.';
    if (keep && document.contains(keep)) { keep.focus({ preventScroll: true }); if (sel) keep.setSelectionRange(sel[0], sel[1]); }
  }
  function updateGroups() {
    Object.keys(groupEls).forEach(function (id) { var x = groupEls[id]; x.meta.textContent = '   ' + x.g.count + '  ·  ' + groupSummary(x.g); });
  }

  function renderTabs() {
    if (!snap) return;
    tabsEl.textContent = '';
    var proj = el('div', 'proj');
    proj.innerHTML = '<svg width="14" height="12" viewBox="0 0 14 12"><path d="M1 2.2C1 1.5 1.5 1 2.2 1h3l1.3 1.4h5.3c.7 0 1.2.5 1.2 1.2v6.2c0 .7-.5 1.2-1.2 1.2H2.2C1.5 11 1 10.5 1 9.8z" fill="var(--dim)"/></svg>';
    proj.appendChild(el('span', '', snap.project || 'Symboard'));
    tabsEl.append(proj, el('div', 'sep'));
    snap.workspaces.forEach(function (w) {
      var b = boards[w.id], n = b ? b.nodes.length : 0;
      var t = el('button', 'wtab' + (w.id === selected ? ' on' : ''));
      t.appendChild(el('span', '', w.name));
      if (w.id === selected) t.appendChild(el('span', 'n', String(n)));
      if (w.id === snap.current) { var h = el('span', 'here'); h.title = 'Open on the Mac now'; t.appendChild(h); }
      t.onclick = function () { follow = w.id === snap.current; select(w.id); };
      tabsEl.appendChild(t);
    });
  }
  function select(id) {
    if (selected === id) { renderTabs(); return; }
    selected = id;
    render(); renderTabs();
    var b = boards[id]; if (b) initialView(b);
    document.title = (b ? b.name : 'Symboard') + ' - Symboard view';
  }

  function post(obj) {
    fetch(BASE + '/input', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(obj) })
      .then(function (r) { if (!r.ok) flash('Typing is not allowed for this console.'); })
      .catch(function () { flash('Could not reach the Mac.'); });
  }
  var flashTimer = null;
  function flash(text) {
    msg.style.display = ''; msg.textContent = text;
    clearTimeout(flashTimer); flashTimer = setTimeout(function () { var b = boards[selected]; msg.style.display = b && b.nodes.length ? 'none' : ''; }, 2200);
  }

  // ---------- 흐름 ----------
  function decode(b64) { var s = atob(b64), a = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i); return a; }
  var es = new EventSource(BASE + '/events');
  if (CONTROL) { var md = document.getElementById('mode'); md.textContent = 'Control link'; md.style.color = '#6FCF97'; }
  es.onopen = function () { msg.textContent = 'Loading the board...'; };
  es.onerror = function () {
    if (es.readyState === 2) {
      world.textContent = ''; tabsEl.textContent = '';
      msg.style.display = ''; msg.textContent = 'Sharing has ended.';
      document.getElementById('liveDot').style.background = 'var(--dim)';
    }
  };
  es.addEventListener('board', function (e) {
    var b = JSON.parse(e.data), first = !boards[b.id];
    boards[b.id] = b;
    if (b.id === selected) { render(); if (first) initialView(b); }
    renderTabs();
  });
  es.addEventListener('meta', function (e) {
    snap = JSON.parse(e.data);
    document.documentElement.setAttribute('data-theme', snap.theme === 'light' ? 'light' : 'dark');
    var live = {};
    snap.consoles.forEach(function (ci) { info[ci.id] = ci; live[ci.id] = true; });
    Object.keys(consoles).forEach(function (id) { if (!live[id]) { consoles[id].term.dispose(); consoles[id].node.remove(); delete consoles[id]; delete info[id]; } });
    snap.consoles.forEach(function (ci) { if (consoles[ci.id]) { var b = boards[ci.workspace], n = b && b.nodes.filter(function (x) { return x.id === ci.id; })[0]; updateConsole(consoles[ci.id], ci, n); } else consoleFor(ci.id); });
    var ids = snap.workspaces.map(function (w) { return w.id; });
    var want = selected;
    if (follow && snap.current) want = snap.current;
    if (ids.indexOf(want) < 0) want = snap.current || ids[0] || null;
    if (want !== selected) select(want); else renderTabs();
    updateGroups();
    document.getElementById('liveN').textContent = snap.live;
    document.getElementById('liveDot').style.background = snap.working ? 'var(--accent)' : (snap.live ? '#3fb950' : 'var(--dim)');
    document.getElementById('working').textContent = snap.working ? '· ' + snap.working + ' working' : '';
  });
  es.addEventListener('out', function (e) {
    var m = JSON.parse(e.data), c = consoleFor(m.id);
    if (m.reset) c.term.reset();
    c.term.write(decode(m.b64));
  });
  es.addEventListener('chat', function (e) {
    var m = JSON.parse(e.data); addEntries(consoleFor(m.id), m.entries, m.reset);
  });
  applyView();
})();
</script>
</body>
</html>
"""#
}
