import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

enum LLMError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case noModel

    var errorDescription: String? {
        switch self {
        case .badURL(let url): return "URL invalide : \(url)"
        case .http(let code, let body): return "HTTP \(code) : \(LLMError.extractMessage(body))"
        case .noModel: return "Aucun modèle disponible sur le serveur (renseigne \"model\" dans la config)."
        }
    }

    private static func extractMessage(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = json["error"] as? String { return msg }
        }
        return String(body.prefix(300))
    }
}

enum LLMClient {
    private static var cachedModel: (baseURL: String, model: String)?

    static func endpoint(_ config: Config, _ path: String) throws -> URL {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: base + path) else { throw LLMError.badURL(config.baseURL) }
        return url
    }

    private static func request(_ url: URL, _ config: Config) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// Modèle configuré, ou le premier listé par le serveur si vide.
    static func resolveModel(_ config: Config) async throws -> String {
        if !config.model.isEmpty { return config.model }
        if let cached = cachedModel, cached.baseURL == config.baseURL { return cached.model }
        struct Models: Decodable { struct M: Decodable { let id: String }; let data: [M] }
        let (data, response) = try await URLSession.shared.data(for: request(try endpoint(config, "/models"), config))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LLMError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard let id = try JSONDecoder().decode(Models.self, from: data).data.first?.id else { throw LLMError.noModel }
        cachedModel = (config.baseURL, id)
        return id
    }

    /// Stream des fragments de texte de `POST /chat/completions` (SSE).
    static func stream(config: Config, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    struct Body: Encodable {
                        let model: String
                        let messages: [ChatMessage]
                        let stream = true
                        let temperature: Double?
                    }
                    struct Chunk: Decodable {
                        struct Choice: Decodable { struct Delta: Decodable { let content: String? }; let delta: Delta }
                        let choices: [Choice]
                    }

                    let model = try await resolveModel(config)
                    var req = request(try endpoint(config, "/chat/completions"), config)
                    req.httpMethod = "POST"
                    req.httpBody = try JSONEncoder().encode(Body(model: model, messages: messages, temperature: config.temperature))

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 4000 { break }
                        }
                        throw LLMError.http(http.statusCode, body)
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(Chunk.self, from: data),
                              let text = chunk.choices.first?.delta.content, !text.isEmpty else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
