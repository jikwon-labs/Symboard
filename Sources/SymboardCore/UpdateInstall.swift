import Foundation

/// 앱 안에서 새 버전으로 바꾸기. 받기·압축 풀기·서명 검사는 앱(UpdateInstaller)이 하고,
/// 여기에는 화면과 무관한 판단과 바꿔 끼우는 스크립트만 둔다.
///
/// 순서: zip 받기 → 같은 볼륨 임시 폴더에 풀기 → 서명·개발자·번들 ID·버전 확인
/// → 도우미 스크립트를 띄우고 앱 종료 → 스크립트가 앱이 끝나길 기다려 번들을 바꾸고 다시 연다.
/// 콘솔은 agentd 가 제 사본으로 들고 있어서(13차) 번들을 바꿔도 끊기지 않는다.
public enum UpdateInstall {
    public enum Problem: Error, Equatable, Sendable {
        /// 다운로드 폴더에서 바로 연 앱. macOS 가 임시 위치(App Translocation)에서 돌려 제자리를 바꿀 수 없다.
        case translocated
        /// 앱이 든 폴더에 쓸 수 없다.
        case notWritable(String)
        /// 지금 앱이 Developer ID 로 서명되지 않았다(개발 빌드). 무엇과 같은지 비교할 기준이 없다.
        case unsignedCurrent
        /// 릴리스에 설치용 zip 이 없다.
        case noAsset
        case downloadFailed
        /// 풀어 보니 Symboard.app 이 없거나 번들 ID·버전이 다르다.
        case badArchive
        /// 서명이 깨졌거나 다른 개발자가 서명했다.
        case signatureMismatch
    }

    public static func isTranslocated(_ bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// `codesign -dv` 출력(stderr)에서 TeamIdentifier 를 꺼낸다. 없거나 "not set"(임시 서명)이면 nil.
    public static func teamID(fromCodesign output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("TeamIdentifier=") else { continue }
            let v = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return v.isEmpty || v == "not set" ? nil : v
        }
        return nil
    }

    /// 풀어 놓은 새 앱이 지금 앱을 대신해도 되는지. 서명 검사 결과와 Info.plist 값을 받아 판단만 한다.
    public static func accept(currentTeam: String?, newTeam: String?, signatureValid: Bool,
                              currentBundleID: String?, newBundleID: String?,
                              expectedVersion: String, newVersion: String?) -> Problem? {
        guard let currentTeam else { return .unsignedCurrent }
        guard signatureValid, newTeam == currentTeam else { return .signatureMismatch }
        guard let newBundleID, newBundleID == currentBundleID,
              let newVersion, UpdateCheck.normalized(newVersion) == UpdateCheck.normalized(expectedVersion) else { return .badArchive }
        return nil
    }

    /// 바꿔 끼우는 도우미. 인자: 앱 pid, 새 앱, 바꿀 앱 자리, 작업 폴더(옛 앱을 잠시 옮겨 둘 곳).
    /// 앱이 1분 안에 끝나지 않으면(종료가 취소됨) 아무것도 바꾸지 않는다. 옮기다 실패하면 옛 앱을 되돌려 놓고 연다.
    public static let swapScript = """
    #!/bin/sh
    PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"
    i=0
    while kill -0 "$PID" 2>/dev/null; do
      sleep 0.2
      i=$((i+1))
      [ "$i" -gt 300 ] && exit 1
    done
    OLD="$WORK/old.app"
    if ! mv "$DEST" "$OLD"; then open "$DEST"; exit 1; fi
    if mv "$NEW" "$DEST"; then
      open "$DEST"
      rm -rf "$WORK"
    else
      mv "$OLD" "$DEST"
      open "$DEST"
      exit 1
    fi
    """
}
