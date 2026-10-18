#!/bin/bash
# orca computer 로 Symboard 에 실제 클릭·키 입력을 보내고, 화면을 /tmp/symui/last.png 로 복사한다.
# 사용: ui.sh state | click X Y [N] | wclick WINDOW_ID X Y | dclick X Y | rclick X Y | type TEXT | key KEY | hotkey CHORD | drag X1 Y1 X2 Y2 | scroll X Y DIR
# 좌표는 창 기준 포인트. 결과로 접근성 트리(이름 있는 것만 줄여서)를 출력한다.
set -uo pipefail
export PATH=/Applications/Orca.app/Contents/Resources/bin:$PATH
# 같은 앱이 여러 개 떠 있으면 SYMBOARD_APP=pid:N 으로 시험 인스턴스만 겨눈다.
APP="${SYMBOARD_APP:-local.symboard.app}"
OUT=/tmp/symui; mkdir -p "$OUT"
cmd="$1"; shift
if [[ "$APP" == pid:* ]]; then
  ACT=/tmp/symtools/activate
  [ -x "$ACT" ] || { mkdir -p /tmp/symtools && swiftc -O "$(dirname "$0")/activate.swift" -o "$ACT"; }
  "$ACT" "${APP#pid:}" > /dev/null; sleep 0.3
fi
run() { orca computer "$@" --app "$APP" --json > "$OUT/last.json" 2>&1; }
case "$cmd" in
  # pid 모드에서 --restore-window 는 번들 id 로 앞으로 가져와 다른 인스턴스를 깨운다. 위의 activate 로 대신한다.
  state) if [[ "$APP" == pid:* ]]; then run get-app-state; else run get-app-state --restore-window; fi ;;
  click) n="${3:-1}"; for _ in $(seq 1 "$n"); do run click --x "$1" --y "$2"; done ;;
  dclick) run click --x "$1" --y "$2" --click-count 2 ;;
  # 확인창(NSAlert)처럼 따로 뜬 창은 창 id(CGWindowList 번호)로 겨눈다. 좌표는 그 창 기준.
  wclick) run click --window-id "$1" --x "$2" --y "$3" ;;
  rclick) run click --x "$1" --y "$2" --mouse-button right ;;
  type) run type-text --text "$1" ;;
  key) run press-key --key "$1" ;;
  hotkey) run hotkey --key "$1" ;;
  drag) run drag --from-x "$1" --from-y "$2" --to-x "$3" --to-y "$4" ;;
  scroll) run scroll --x "$1" --y "$2" --direction "$3" ;;
  *) echo "unknown $cmd"; exit 2 ;;
esac
# 입력이 들어가기 전에 거부된 경우(aborted/requires)는 보내진 것이 없으므로 pid 활성화 뒤 한 번 다시 보낸다.
if [[ "$APP" == pid:* ]] && grep -q '"window_not_focused"' "$OUT/last.json" && grep -Eq 'aborted|requires the target' "$OUT/last.json"; then
  "$ACT" "${APP#pid:}" > /dev/null; sleep 0.5
  orca computer get-app-state --app "$APP" --json > /dev/null 2>&1
  case "$cmd" in
    click) run click --x "$1" --y "$2" ;;
    type) run type-text --text "$1" ;;
    key) run press-key --key "$1" ;;
    hotkey) run hotkey --key "$1" ;;
  esac
fi
if grep -q '"window_not_focused"' "$OUT/last.json"; then
  # 창 초점이 바뀌었다는 뜻. 클릭이 이미 들어갔을 수도 있으므로 다시 보내지 않고 상태만 되살린다.
  if [[ "$APP" == pid:* ]]; then "$ACT" "${APP#pid:}" > /dev/null
  else orca computer get-app-state --app "$APP" --restore-window --json > /dev/null 2>&1; fi
  echo "(window focus changed; restored, not retried)"
fi
python3 - "$OUT" "${UI_TREE:-short}" <<'PY'
import json, sys, shutil
out, mode = sys.argv[1], sys.argv[2]
d = json.load(open(out + "/last.json"))
if not d.get("ok"):
    print("ERROR", json.dumps(d.get("error"), ensure_ascii=False)); sys.exit(0)
r = d.get("result", {})
s = r.get("screenshot") or {}
if s.get("path"):
    shutil.copy(s["path"], out + "/last.png")
    print("screenshot", out + "/last.png", "scale", s.get("scale"))
v = r.get("verification")
if v: print("verification", v)
t = (r.get("snapshot") or {}).get("treeText", "")
if mode == "full": print(t)
elif mode == "short":
    lines = [l for l in t.splitlines() if l.strip() and not l.strip().split(" ", 1)[-1] in ("button", "image", "group")]
    print("\n".join(lines[:80]))
PY
