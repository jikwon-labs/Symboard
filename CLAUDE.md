# Symboard

macOS 보드 앱(Swift 6 툴체인, SwiftPM). 콘솔(claude·codex·셸)을 캔버스 노드로 띄운다.

## 작업은 항상 워크트리에서

작업을 시작하면 **메인 폴더에서 고치지 않고** `.claude/worktree/<브랜치>` 에 워크트리를 만들어 그 안에서 한다.

```bash
git fetch origin
git worktree add .claude/worktree/<브랜치> -b <브랜치> origin/main
cd .claude/worktree/<브랜치>
```

- 브랜치 이름은 `feat/…`, `fix/…`, `perf/…`, `chore/…` 처럼 커밋 머리말을 따른다.
- 메인 폴더의 `Sources/` `Tests/` `scripts/` `Resources/` `Vendor/` `Package.swift` 는 훅(`.claude/hooks/guard.sh`)이 수정을 막는다. 워크트리 안의 같은 파일은 막지 않는다.
- 커밋·push·PR 은 사용자가 요청했을 때만 한다. 머지 뒤에는 `git worktree remove` 와 브랜치 삭제로 정리한다.

## 빌드와 검증

- `swift build`, `swift test` — 보고 전에 항상 `swift test` 를 돌린다.
- `scripts/bundle.sh` — 서명 없는 `build/Symboard.app` 번들까지 확인할 때.
- **검증 때 앱을 띄우지 않는다.** 화면 확인이 필요하면 무엇을 어떻게 보면 되는지 사용자에게 적어 준다. 훅이 앱 실행 명령을 막는다.
- `scripts/drive.sh` 는 실행 중인 앱을 조작하는 디버그 통로다. 사용자가 요청했을 때만 쓴다.

## 구조

- `SymboardCore` — 화면과 무관한 로직. 테스트(`Tests/SymboardCoreTests`)는 이 타깃만 본다.
- `Symboard` — AppKit 중심 앱(Swift 5 언어 모드). 보조 패널만 SwiftUI.
- `SymboardMCP` — claude 콘솔에 붙는 stdio MCP 서버. 번들의 `Contents/MacOS` 에 함께 들어간다.

## 규칙

- **화면 글 번역**: 새 UI 문구는 `Sources/SymboardCore/Strings.swift` 의 `ko` 표에도 넣는다. 열쇠는 영어 원문 그대로이고, `%@` `%d` 같은 자리 표시 개수가 원문과 같아야 한다(V10·V12 테스트가 검사).
- **결정 기록**: 설계 판단은 `DECISIONS.md` 에 덧붙인다.
- **버전**: `Sources/SymboardCore/Version.swift` 한 곳에만 둔다. 배포는 사용자가 `scripts/release.sh <버전>` 으로 직접 한다(공증·태그·push·GitHub 릴리스). Claude 는 `DRY_RUN=1` 로만 돌릴 수 있다.
- **SwiftTerm**: `Vendor/SwiftTerm` 은 1.11.2 에 패치를 얹은 사본이다(`Vendor/SwiftTerm/PATCHES.md`). 버전을 올리지 않는다.
- **커밋 메시지**: `feat:` `fix:` `perf:` `chore:` `docs:` 머리말 뒤에 한국어 쉬운 말.
- `PLAN*.md` `REPORT*.md` 는 git 에 넣지 않는 로컬 문서다.
