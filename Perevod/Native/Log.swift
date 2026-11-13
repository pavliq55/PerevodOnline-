import UIKit

/// Журнал работы приложения — на наш сервер (/api/diag → tts-server/log.jsonl, t:"app"), чтобы видеть ошибки и скорость.
/// Тексты переводов сюда не пишем (они и так в записи t:"live"), только события и время.
enum Log {
    static let v: String = {
        let i = Bundle.main.infoDictionary
        return "ios \(i?["CFBundleShortVersionString"] as? String ?? "?").\(i?["CFBundleVersion"] as? String ?? "?")"
    }()
    static let device: String = {
        var s = utsname(); uname(&s)
        return withUnsafeBytes(of: &s.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    static func send(_ ev: String, _ f: [String: Any] = [:]) {
        guard Shared.token != nil else { return }
        var b = f; b["t"] = "app"; b["ev"] = ev; b["v"] = v
        if let e = b["err"] as? String { b["err"] = String(e.prefix(300)) }   // сервер не берёт записи длиннее 2000 знаков
        Task.detached(priority: .utility) { _ = try? await Api.json("/api/diag", b, timeout: 8) }
    }

    static func launch() {
        send("launch", ["ios": UIDevice.current.systemVersion, "dev": device,
                        "group": Shared.group.hasSuffix(".tapny") ? "base" : "team"])
    }

    static func ms(since t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
}
