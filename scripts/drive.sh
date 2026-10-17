#!/bin/bash
# 실행 중인 Symboard 에 디버그 명령을 보내고 결과를 출력한다.
# 사용: scripts/drive.sh '<JSON 명령 배열>' [상태 폴더]
set -euo pipefail
HOME_DIR="${2:-${SYMBOARD_HOME:-$HOME/Library/Application Support/Symboard}}"
DBG="$HOME_DIR/debug"
mkdir -p "$DBG"
rm -f "$DBG/result.txt"
printf '%s' "$1" > "$DBG/cmd.json.tmp"
mv "$DBG/cmd.json.tmp" "$DBG/cmd.json"
for _ in $(seq 1 240); do
  if [ -f "$DBG/result.txt" ]; then cat "$DBG/result.txt"; echo; exit 0; fi
  sleep 0.5
done
echo "timeout waiting for result" >&2
exit 1
