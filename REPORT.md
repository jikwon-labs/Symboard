# Symboard 보고

## 한 줄 결론

계획한 14개 기능을 모두 만들었고, 완료 기준(release 빌드·테스트 37개 통과, `scripts/bundle.sh` 로 앱 생성, `open` 으로 띄워 터미널 3개·vim·claude 후 재실행 시 같은 자리 복원)을 직접 다시 확인했다.

## 된 것

- **보드:** 무한 캔버스 이동·확대, 노드 끌기·크기 조절, 작업공간 탭.
- **터미널 노드:** 진짜 PTY(SwiftTerm). vim 열고 닫기, Ctrl-C, Claude Code·Codex 화면 확인.
- **상태:** Claude Code 훅을 `--settings` 로 주입(사용자 `~/.claude` 는 건드리지 않음). 그 밖의 CLI 는 출력 정지 시간으로 판정. 모든 노드를 모아 보는 Mission 패널.
- **이어하기:** 노드 위치·크기·CLI 를 자동 저장한다. 다시 켜면 `claude --resume <id>`, `codex resume <id>` 로 이전 대화가 돌아오는 것을 hello 한 번으로 확인했다.
- **나머지:** 컴포저(12개)·팀, 루프(간격·유휴·출력, 목표 문구로 자동 종료), 넘겨주기, 메모 노드·펜·이미지 표시, 웹 타일·인스펙터, git 카드, 스튜디오(코드·마크다운·PDF·다이어그램 PNG), 사용량, 계정 프로필, 메모리.
- **고친 버그:**
  - 앱을 Claude Code 안에서 띄우면 자식 claude 가 대화 기록을 저장하지 않던 문제(물려받은 세션 변수 제거).
  - `/tmp` → `/private/tmp` 경로 차이 때문에 이어하기가 깨지던 문제.
  - 가려진 창에서 App Nap 때문에 타이머가 멈추던 문제.
  - 스튜디오 PDF 내보내기 첫 구현이 끝없이 쪽을 만들어 파일이 1.4GB 까지 커진 문제. 바로 앱을 죽이고 파일을 지운 뒤 방식을 바꿨다.

## 포기한 것과 이유

포기한 항목은 없다. 확인 범위가 좁은 것만 적는다(자세한 내용은 `README.md` 의 "포기한 것과 한계").

- **htop:** 설치돼 있지 않아 확인하지 못했다.
- **입력 기다림 상태:** 실제 권한 요청을 일으키지 않으려고 단위 테스트로만 확인했다.
- **넘겨주기:** 에이전트에 실제 요약 일을 시키지 않으려고 가짜 에이전트로 확인했다.
- **웹 인스펙터:** 공개 API 가 없어 WebKit 내부 객체에 기댄다.

## 실행 방법

```bash
cd ~/Documents/side/symboard
scripts/bundle.sh          # 이미 만들어져 있으면 생략 가능
open build/Symboard.app
```

처음 열면 시험 때 만든 노드 3개(셸 2개, /tmp/symclaude 의 claude 1개)가 보인다. 필요 없으면 노드 오른쪽 위 X 로 닫으면 된다.

## 아침에 직접 눌러 볼 순서

1. **이어하기:** 도구 막대 New Terminal → Program 을 Claude Code, Folder 를 아무 작업 폴더로 → Create. hello 를 보내고 Cmd+Q 로 끈 뒤 다시 `open build/Symboard.app`. 같은 자리에 같은 대화가 돌아오는지 본다.
2. **상태 표시:** 오른쪽 패널 Mission 을 연다. 그 claude 노드에 짧은 질문을 보내면 Working(초록) → Idle(파랑)로 바뀐다. 줄을 누르면 그 노드로 이동한다.
3. **팀과 루프:** Composer 에서 Shell 4개를 띄운다. 그중 한 노드 헤더의 `...` → Add Loop... 에서 "When idle for N seconds" 를 고르고 Message 를 `date` 로 둔다. 패널 Loops 탭에서 실행 횟수가 올라가는지 본다.
