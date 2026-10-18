import Foundation

/// Связь с сервером переводчика. Все запросы — с ключом этого айфона (d1.…) в заголовке X-Pin.
enum Api {
    static let base = Shared.base
    struct Fail: Error, LocalizedError { let message: String; var errorDescription: String? { message } }

    static var key: String? { Shared.token }

    static func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil, type: String = "application/json",
                        key: String? = nil, timeout: TimeInterval = 20) async throws -> Data {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var r = URLRequest(url: c.url!)
        r.httpMethod = body == nil ? "GET" : "POST"; r.httpBody = body; r.timeoutInterval = timeout
        if let k = key ?? self.key { r.setValue(k, forHTTPHeaderField: "X-Pin") }
        if body != nil { r.setValue(type, forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Fail(message: "pin") }
        if code == 429 { throw Fail(message: "Много запросов — подожди немного") }
        if code >= 400 {
            let e = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Fail(message: e ?? "Ошибка сервера \(code)")
        }
        return data
    }

    static func json(_ path: String, _ obj: [String: Any], key: String? = nil, timeout: TimeInterval = 20) async throws -> [String: Any] {
        let d = try await request(path, body: try JSONSerialization.data(withJSONObject: obj), key: key, timeout: timeout)
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }

    /// Вход: PIN → ключ этого айфона (PIN дальше нигде не хранится).
    static func login(pin: String) async throws -> String {
        _ = try await json("/api/check", [:], key: pin)
        let id = Shared.defaults.string(forKey: "devId") ?? UUID().uuidString
        Shared.defaults.set(id, forKey: "devId")
        let d = try await json("/api/device", ["id": id], key: pin)
        guard let t = d["token"] as? String else { throw Fail(message: "Не получилось войти") }
        return t
    }

    struct Tr { let mine: Bool; let src: String; let to: String; let out: String }
    static func parseTr(_ d: [String: Any]?) -> Tr? {
        guard let d, let out = d["out"] as? String, !out.isEmpty else { return nil }
        return Tr(mine: d["mine"] as? Bool ?? false, src: d["src"] as? String ?? "", to: d["to"] as? String ?? "ru", out: out)
    }

    static func translate(_ text: String, to: String, force: String? = nil, draft: Bool = false) async throws -> Tr {
        var b: [String: Any] = ["text": text, "to": to]
        if let force { b["force"] = force }
        if draft { b["draft"] = true }
        guard let t = parseTr(try await json("/api/tr", b, timeout: draft ? 8 : 20)) else { throw Fail(message: "Не получилось перевести") }
        return t
    }

    /// Запасное распознавание целой записи (WAV 16 кГц), сервер сразу и переводит.
    static func stt(wav: Data, to: String) async throws -> (text: String, tr: Tr?) {
        let d = try await request("/api/stt", query: [URLQueryItem(name: "to", value: to)], body: wav, type: "audio/wav", timeout: 40)
        let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        return ((j["text"] as? String) ?? "", parseTr(j["tr"] as? [String: Any]))
    }

    static func photo(jpeg: Data) async throws -> String {
        let d = try await request("/api/photo", body: jpeg, type: "image/jpeg", timeout: 40)
        let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        guard let o = j["out"] as? String, !o.isEmpty else { throw Fail(message: (j["error"] as? String) ?? "Не получилось прочитать фото") }
        return o
    }

    static func voice(_ text: String, lang: String) async throws -> Data {
        try await request("/api/tts", query: [URLQueryItem(name: "v", value: "8"), URLQueryItem(name: "l", value: lang),
                                              URLQueryItem(name: "q", value: String(text.prefix(1000)))], timeout: 15)
    }
}
