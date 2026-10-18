import Carbon
// 입력 소스(한글·ABC)를 바꾼다. 7차 한글 입력기 시험용.
// 사용: inputsrc list | current | select ID
let args = CommandLine.arguments
func props(_ s: TISInputSource) -> String {
    let id = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue() as String
    return id
}
let list = TISCreateInputSourceList([kTISPropertyInputSourceIsSelectCapable: true] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
switch args.count > 1 ? args[1] : "list" {
case "current": print(props(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
case "select": if let s = list.first(where: { props($0) == args[2] }) { print(TISSelectInputSource(s)) } else { print("none") }
default: for s in list { print(props(s)) }
}
