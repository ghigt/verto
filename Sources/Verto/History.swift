import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    var date: Date
    var action: String
    var original: String
    var result: String
    /// Conversation complète, pour pouvoir la rouvrir et continuer à l'ajuster.
    var messages: [ChatMessage]
}

/// Historique local, stocké en clair dans ~/.config/verto/history.json.
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    var limit: Int

    private static var fileURL: URL { Config.directory.appendingPathComponent("history.json") }

    init(limit: Int) {
        self.limit = limit
        if let data = try? Data(contentsOf: Self.fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    /// Ajoute ou met à jour une entrée et la remonte en tête.
    func upsert(_ entry: HistoryEntry) {
        guard limit > 0 else { return }
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func search(_ query: String) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.original.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.result.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func save() {
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
