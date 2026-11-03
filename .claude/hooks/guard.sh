#!/bin/bash
# PreToolUse 훅: 앱 실행·배포 명령과 메인 폴더 소스 수정을 막는다. 막을 때는 exit 2.
set -uo pipefail
input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"

block() { echo "guard: $*" >&2; exit 2; }

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    if grep -Eq '(^|[;&|[:space:]])open[[:space:]].*Symboard\.app' <<<"$cmd" \
      || grep -Eq 'Symboard\.app/Contents/MacOS/Symboard([[:space:];&|]|$)' <<<"$cmd" \
      || grep -Eq '\.build/[^[:space:]]*/Symboard([[:space:];&|]|$)' <<<"$cmd" \
      || grep -Eq '(^|[;&|[:space:]])swift[[:space:]]+run' <<<"$cmd"; then
      block "검증 때 앱을 띄우지 않는다. swift build/test 까지만 하고 화면 확인은 사용자에게 안내한다."
    fi
    if grep -Eq 'scripts/release\.sh' <<<"$cmd" && ! grep -Eq 'DRY_RUN=1' <<<"$cmd"; then
      block "배포는 사용자가 직접 한다. 확인만 하려면 DRY_RUN=1 scripts/release.sh <버전>."
    fi
    if grep -Eq 'gh[[:space:]]+release[[:space:]]+(create|upload|edit|delete)' <<<"$cmd"; then
      block "GitHub 릴리스는 사용자가 직접 만든다."
    fi
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
    [ -n "$path" ] || exit 0
    dir="$(dirname "$path")"
    while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do dir="$(dirname "$dir")"; done
    common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
    main="$(dirname "$common")"
    # 메인 폴더(워크트리가 아닌 곳)의 소스만 막는다.
    if [ "$top" = "$main" ]; then
      case "$path" in
        "$main"/Sources/*|"$main"/Tests/*|"$main"/scripts/*|"$main"/Resources/*|"$main"/Vendor/*|"$main"/Package.swift)
          block "메인 폴더에서 소스를 고치지 않는다. .claude/worktree/<브랜치> 에 워크트리를 만들어 그 안에서 고친다(CLAUDE.md)."
          ;;
      esac
    fi
    ;;
esac
exit 0
