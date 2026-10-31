#!/bin/bash
# 새 버전을 배포한다: 버전 올리기 → 시험 → 서명·공증 빌드 → 커밋·태그 → push → GitHub 릴리스(zip 첨부).
# 사용: scripts/release.sh <새 버전>        예) scripts/release.sh 0.2.0
#       DRY_RUN=1 scripts/release.sh 0.2.0  빌드·공증까지만 하고 커밋·push·릴리스는 하지 않는다(버전 파일은 되돌린다).
# 필요한 것: main 에서 깨끗한 작업 트리, Developer ID 인증서, `symboard-notary` 공증 계정, 로그인된 gh.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
NEW="${NEW#v}"
VERSION_FILE=Sources/SymboardCore/Version.swift
CUR="$(sed -nE 's/.*version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$VERSION_FILE")"

die() { echo "release: $*" >&2; exit 1; }

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "버전을 x.y.z 로 주세요 (지금 $CUR)"
# 새 버전이 지금보다 높아야 한다(정렬해서 마지막이 새 버전이고 둘이 다를 것).
[ "$NEW" != "$CUR" ] && [ "$(printf '%s\n%s\n' "$CUR" "$NEW" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$NEW" ] \
  || die "$NEW 는 지금 버전 $CUR 보다 높아야 한다"

[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "main 브랜치에서 실행한다"
git diff --quiet && git diff --cached --quiet || die "커밋하지 않은 변경이 있다"
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "origin/main 과 다르다(pull 또는 push 먼저)"
git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null && die "태그 v$NEW 가 이미 있다"
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || die "gh 로그인이 필요하다 (gh auth login)"

PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"

echo "== $CUR → $NEW"
sed -i '' -E "s/(version = \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1$NEW\2/" "$VERSION_FILE"
restore() { git checkout -- "$VERSION_FILE"; }
trap 'echo "release: 실패해서 버전 파일을 되돌린다" >&2; restore' ERR

echo "== 시험"
swift test

echo "== 서명·공증 빌드 (몇 분 걸림)"
NOTARIZE=1 scripts/bundle.sh
[ -f build/Symboard.zip ] || die "build/Symboard.zip 이 없다"

if [ "${DRY_RUN:-0}" = 1 ]; then
  trap - ERR
  restore
  echo "== DRY_RUN: build/Symboard.zip 까지 만들었다. 커밋·push·릴리스는 하지 않았다."
  exit 0
fi

# 릴리스 노트: 설치 안내 + 지난 태그 뒤 커밋 제목.
NOTES="$(mktemp)"
{
  echo "## 바뀐 것"
  if [ -n "$PREV_TAG" ]; then git log --no-merges --pretty='- %s' "$PREV_TAG..HEAD"; else git log --no-merges --pretty='- %s'; fi
  echo
  echo "## 설치"
  echo "1. \`Symboard.zip\` 을 받아 압축을 푼다."
  echo "2. \`Symboard.app\` 을 응용 프로그램 폴더로 옮겨 연다(덮어써도 상태는 그대로)."
  echo
  echo "Developer ID 로 서명하고 Apple 공증을 받았다. macOS 14 이상, Apple Silicon."
} > "$NOTES"

echo "== 릴리스 노트"
cat "$NOTES"
echo
read -r -p "v$NEW 를 커밋·태그·push 하고 릴리스를 만들까요? [y/N] " ok
if [ "$ok" != y ] && [ "$ok" != Y ]; then
  trap - ERR
  restore
  rm -f "$NOTES"
  die "취소했다(버전 파일을 되돌렸다)"
fi

trap - ERR
git add "$VERSION_FILE"
git commit -m "chore: v$NEW 배포"
git tag -a "v$NEW" -m "Symboard $NEW"
git push origin main "v$NEW"
gh release create "v$NEW" build/Symboard.zip --title "Symboard $NEW" --notes-file "$NOTES"
rm -f "$NOTES"
echo "== 끝: $(gh release view "v$NEW" --json url -q .url)"
