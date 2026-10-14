// SnapNest 2.0 private additions. Local development only.
import Foundation

public enum LauncherSearch {
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func matches(title: String, query: String) -> Bool {
        let latin = normalized(title.applyingTransform(.toLatin, reverse: false) ?? title)
        let words = latin.split { !$0.isLetter && !$0.isNumber }
        let compact = words.joined()
        let initials = words.compactMap(\.first).map(String.init).joined()
        let original = normalized(title)
        return normalized(query).split(whereSeparator: \.isWhitespace).allSatisfy { token in
            original.contains(token) || latin.contains(token) || compact.contains(token) || initials.contains(token)
        }
    }

    /// Only explicit HTTP(S) destinations are supported; never interpret a command or file URL.
    public static func webURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }
}
