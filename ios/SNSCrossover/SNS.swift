import SwiftUI

/// 表示できる SNS の一覧。ここに追加すれば選べる SNS が増える。
enum SNS: String, CaseIterable, Identifiable {
    case youtube, x, instagram, threads

    var id: String { rawValue }

    var name: String {
        switch self {
        case .youtube: "YouTube"
        case .x: "X"
        case .instagram: "Instagram"
        case .threads: "Threads"
        }
    }

    var color: Color {
        switch self {
        case .youtube: Color(red: 1.0, green: 0.0, blue: 0.2)
        case .x: Color.primary
        case .instagram: Color(red: 0.88, green: 0.19, blue: 0.42)
        case .threads: Color(red: 0.55, green: 0.55, blue: 1.0)
        }
    }

    var home: URL {
        switch self {
        case .youtube: URL(string: "https://m.youtube.com/")!
        case .x: URL(string: "https://x.com/home")!
        case .instagram: URL(string: "https://www.instagram.com/")!
        case .threads: URL(string: "https://www.threads.com/")!
        }
    }

    /// この SNS の画面の中で開いてよいドメイン（それ以外のリンクは Safari で開く）
    var domains: [String] {
        switch self {
        case .youtube: ["youtube.com", "youtu.be", "google.com"]
        case .x: ["x.com", "twitter.com"]
        case .instagram: ["instagram.com", "facebook.com"]
        case .threads: ["threads.com", "threads.net", "instagram.com", "facebook.com"]
        }
    }
}

/// どの SNS でも開いてよいログイン用ドメイン（「Google でログイン」など）
let authDomains = ["accounts.google.com", "appleid.apple.com", "facebook.com", "instagram.com"]

extension URL {
    func hostMatches(_ domains: [String]) -> Bool {
        guard let host = host()?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// 上下に並べる 2 つの SNS の組み合わせ（「画面セット」）
struct ScreenSet: Equatable, Identifiable {
    var id: String { "\(top.rawValue),\(bottom.rawValue)" }

    var top: SNS
    var bottom: SNS

    subscript(slot: Int) -> SNS {
        get { slot == 0 ? top : bottom }
        set { if slot == 0 { top = newValue } else { bottom = newValue } }
    }

    static let defaults = [
        ScreenSet(top: .youtube, bottom: .x),
        ScreenSet(top: .instagram, bottom: .threads),
    ]

    /// 保存用の文字列 "youtube,x;instagram,threads" との変換
    static func decode(_ text: String) -> [ScreenSet] {
        let sets = text.split(separator: ";").compactMap { part -> ScreenSet? in
            let items = part.split(separator: ",").compactMap { SNS(rawValue: String($0)) }
            return items.count == 2 && items[0] != items[1] ? ScreenSet(top: items[0], bottom: items[1]) : nil
        }
        return sets.isEmpty ? defaults : sets
    }

    static func encode(_ sets: [ScreenSet]) -> String {
        sets.map { "\($0.top.rawValue),\($0.bottom.rawValue)" }.joined(separator: ";")
    }
}
