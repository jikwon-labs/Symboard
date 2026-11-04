# rrweb 2.1.7

공유 보기에서 웹 타일 페이지를 옮겨 그리는 데 쓴다(DECISIONS 15차).

- `record.js` — npm `@rrweb/record@2.1.7` 의 `dist/record.umd.min.cjs`. 맥의 웹 타일(WKWebView) 격리 세계에 넣어 페이지 구조와 바뀐 부분을 기록한다.
- `replay.js` — npm `@rrweb/replay@2.1.7` 의 `dist/replay.umd.min.cjs`. 공유 서버가 `/v|c/<토큰>/rrweb.js` 로 보내고, 보기 화면이 받은 기록을 다시 그린다.
- 두 파일 모두 원본에서 마지막 줄(`//# sourceMappingURL=…`)만 뗐다. 기록과 재생은 같은 버전이어야 하므로 함께 올린다.
- 라이선스: MIT(`LICENSE`).

sha256
- record.js `35ae6756411569dc6bc7519ac9572ae6a6da76fb181fda475456fd94fbad6259`
- replay.js `b5e5ed2d342bd113115b7aca1dd9e6b6fd65c495d6725810cbf92103d09d1fd0`
