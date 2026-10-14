import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
check(LauncherSearch.matches(title: "Visual Studio Code", query: "visual code"), "all query tokens")
check(LauncherSearch.matches(title: "微信", query: "weixin"), "Chinese pinyin")
check(LauncherSearch.matches(title: "微信", query: "wx"), "Chinese initials")
check(LauncherSearch.matches(title: "Café", query: "CAFE"), "diacritic and case folding")
check(!LauncherSearch.matches(title: "Safari", query: "mail"), "unrelated result excluded")
check(LauncherSearch.webURL(" https://example.com/a ")?.host == "example.com", "valid HTTPS")
check(LauncherSearch.webURL("http://localhost:8080") != nil, "explicit HTTP allowed")
for invalid in ["file:///tmp/a", "javascript:alert(1)", "https://", "example.com", "https://user:secret@example.com", "https://exa mple.com"] {
    check(LauncherSearch.webURL(invalid) == nil, "reject invalid or unsafe URL: \(invalid)")
}
print("Launcher checks passed")
