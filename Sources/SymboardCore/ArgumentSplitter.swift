import Foundation

/// 셸처럼 공백으로 인자를 나눈다. 작은따옴표·큰따옴표로 묶은 부분은 한 인자로 본다.
public enum ArgumentSplitter {
    public static func split(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character?
        var has = false
        var escape = false
        for c in s {
            if escape { cur.append(c); escape = false; continue }
            if c == "\\" && quote != "'" { escape = true; has = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { cur.append(c) }
                continue
            }
            if c == "\"" || c == "'" { quote = c; has = true; continue }
            if c.isWhitespace {
                if has { out.append(cur); cur = ""; has = false }
                continue
            }
            cur.append(c); has = true
        }
        if has { out.append(cur) }
        return out
    }
}
