// pid 로 앱을 앞으로 가져온다. 같은 번들 id 의 Symboard 가 둘 이상 떠 있으면
// orca computer 의 --restore-window 가 다른 쪽을 앞으로 가져와 키 입력이 거부된다(7차).
// 사용: activate PID
import AppKit
guard CommandLine.arguments.count > 1, let pid = pid_t(CommandLine.arguments[1]) else { print("usage: activate PID"); exit(2) }
print(NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) ?? false)
