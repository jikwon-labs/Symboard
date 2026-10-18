# SwiftTerm 사본

원본: https://github.com/migueldeicaza/SwiftTerm 1.11.2 (b1262db5), MIT(`LICENSE`).
`Sources/SwiftTerm` 만 옮기고 `Package.swift` 는 라이브러리 대상 하나로 줄였다.

## 고친 곳

1. `LocalProcess.childProcessRead` — 읽기 작업이 끝났을 때(`done == true`)만 다음 읽기를 건다.
   원래는 낮은 수위 1 바이트로 조각이 올 때마다(`done == false` 포함) 새 `io.read` 를 걸어서,
   끝나지 않은 `OS_dispatch_operation` 과 직렬 큐가 출력 양에 비례해 쌓였다.
   Symboard 5차 많이 띄우기 시험(셸 24개 × 3000줄 다섯 번)에서 14만 6천 개, 약 65MB 까지 늘었다.
