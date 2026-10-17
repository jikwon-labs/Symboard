import Foundation

/// 터미널 노드 하나를 띄우기 위한 실행 정보.
public struct LaunchPlan: Equatable, Sendable {
    /// 사용자 셸에 넘길 명령 인자. 첫 원소가 프로그램 이름이다.
    public var command: [String]
    public var environment: [String: String]
    public var cwd: String
    /// 이번 실행이 이어하기인지.
    public var isResume: Bool
    /// 실행 후 TerminalSpec 에 기록할 세션 id (claude 처럼 앱이 정할 수 있을 때).
    public var sessionID: String?

    public init(command: [String], environment: [String: String], cwd: String, isResume: Bool, sessionID: String?) {
        self.command = command; self.environment = environment; self.cwd = cwd
        self.isResume = isResume; self.sessionID = sessionID
    }
}

public enum HookState: String, Sendable, CaseIterable {
    case working
    case idle
    case waiting
    case exited
}

public enum LaunchPlanner {
    /// Claude Code 훅 이벤트를 앱 상태로 바꾸는 표. 이벤트 이름은 공식 hooks 문서(code.claude.com/docs/en/hooks)에서 확인했다.
    public static let claudeHookMap: [(event: String, matcher: String?, state: HookState)] = [
        ("SessionStart", nil, .idle),
        ("UserPromptSubmit", nil, .working),
        ("PreToolUse", nil, .working),
        ("PostToolUse", nil, .working),
        ("PermissionRequest", nil, .waiting),
        ("Notification", "permission_prompt|elicitation_dialog|agent_needs_input", .waiting),
        ("Notification", "idle_prompt", .idle),
        ("Stop", nil, .idle),
        ("StopFailure", nil, .idle),
        ("SessionEnd", nil, .exited),
    ]

    /// `--settings` 로 넘길 훅 설정 JSON. 사용자의 ~/.claude 설정은 건드리지 않는다.
    /// 훅은 앱이 자식 프로세스에 준 SYMBOARD_STATUS_FILE 에 상태 단어를 쓴다.
    public static func claudeHookSettingsJSON() -> String {
        var hooks: [String: [[String: Any]]] = [:]
        for entry in claudeHookMap {
            let cmd = "[ -n \"$SYMBOARD_STATUS_FILE\" ] && printf '\(entry.state.rawValue)' > \"$SYMBOARD_STATUS_FILE\" || true"
            var group: [String: Any] = ["hooks": [["type": "command", "command": cmd, "timeout": 5]]]
            if let m = entry.matcher { group["matcher"] = m }
            hooks[entry.event, default: []].append(group)
        }
        let data = try! JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// - Parameters:
    ///   - claudeSessionExists: claude 세션 기록이 디스크에 있는지. 없으면 --resume 대신 같은 id 로 새로 시작한다.
    public static func plan(for spec: TerminalSpec, nodeID: UUID, statusFile: String,
                            profile: AccountProfile?, claudeSessionExists: Bool,
                            defaultShell: String) -> LaunchPlan {
        var env: [String: String] = [
            "SYMBOARD_NODE_ID": nodeID.uuidString,
            "SYMBOARD_STATUS_FILE": statusFile,
        ]
        if let profile {
            switch profile.agent {
            case .claude: env["CLAUDE_CONFIG_DIR"] = profile.configDir
            case .codex: env["CODEX_HOME"] = profile.configDir
            default: break
            }
        }

        switch spec.agent {
        case .shell:
            return LaunchPlan(command: [defaultShell, "-l"], environment: env, cwd: spec.cwd, isResume: false, sessionID: nil)

        case .custom:
            let exe = spec.executable ?? defaultShell
            return LaunchPlan(command: [exe] + spec.extraArgs, environment: env, cwd: spec.cwd, isResume: false, sessionID: nil)

        case .claude:
            let settings = claudeHookSettingsJSON()
            if spec.hasLaunched, let sid = spec.sessionID, claudeSessionExists {
                return LaunchPlan(command: ["claude", "--resume", sid, "--settings", settings] + spec.extraArgs,
                                  environment: env, cwd: spec.cwd, isResume: true, sessionID: sid)
            }
            let sid = spec.sessionID ?? UUID().uuidString.lowercased()
            return LaunchPlan(command: ["claude", "--session-id", sid, "--settings", settings] + spec.extraArgs,
                              environment: env, cwd: spec.cwd, isResume: false, sessionID: sid)

        case .codex:
            if spec.hasLaunched {
                // codex 는 시작 전에 세션 id 를 정할 수 없다. 찾아 둔 id 가 있으면 그것을, 없으면 이 폴더의 마지막 세션을 잇는다.
                let target = spec.sessionID.map { [$0] } ?? ["--last"]
                return LaunchPlan(command: ["codex", "resume"] + target + spec.extraArgs,
                                  environment: env, cwd: spec.cwd, isResume: true, sessionID: spec.sessionID)
            }
            return LaunchPlan(command: ["codex"] + spec.extraArgs, environment: env, cwd: spec.cwd, isResume: false, sessionID: nil)
        }
    }

    /// 앱을 띄운 쪽(예: 다른 Claude Code 세션)에서 물려받으면 안 되는 세션 표시 변수.
    /// CLAUDE_CODE_CHILD_SESSION 이 남아 있으면 자식 claude 가 대화 기록을 저장하지 않아 이어하기가 깨진다(직접 확인).
    public static let inheritedSessionKeys: Set<String> = [
        "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_EXECPATH", "CLAUDE_CODE_SSE_PORT", "CLAUDE_PID",
    ]

    public static func sanitized(_ env: [String: String]) -> [String: String] {
        env.filter { !inheritedSessionKeys.contains($0.key) }
    }

    /// claude 는 심볼릭 링크를 푼 실제 경로(/tmp → /private/tmp)로 프로젝트 폴더를 정한다(직접 확인).
    public static func resolvedPath(_ path: String) -> String {
        // resolvingSymlinksInPath 는 /private 를 도로 떼어 내므로 realpath 를 쓴다.
        guard let p = realpath(path, nil) else { return path }
        defer { free(p) }
        return String(cString: p)
    }

    /// claude 가 프로젝트 기록을 두는 폴더 이름. cwd 의 ASCII 영숫자가 아닌 문자를 '-' 로 바꾼다.
    public static func claudeProjectDirName(for cwd: String) -> String {
        String(cwd.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" })
    }

    public static func claudeSessionExists(sessionID: String, cwd: String, configDir: String?) -> Bool {
        let base = configDir ?? (NSHomeDirectory() + "/.claude")
        let path = "\(base)/projects/\(claudeProjectDirName(for: resolvedPath(cwd)))/\(sessionID).jsonl"
        return FileManager.default.fileExists(atPath: path)
    }

    /// 사용자 로그인 셸을 거쳐 실행하는 인자 배열. nvm 처럼 .zshrc 에서 잡히는 PATH 를 쓰려면 -i 가 필요하다.
    public static func shellWrapped(_ command: [String], shell: String) -> (executable: String, args: [String]) {
        if command.first == shell { return (shell, Array(command.dropFirst())) }
        return (shell, ["-l", "-i", "-c", "exec \"$0\" \"$@\""] + command)
    }
}
