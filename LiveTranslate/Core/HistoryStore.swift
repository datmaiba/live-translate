import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let direction: Direction
    let source: String
    let translation: String
}

/// Local-only history (JSON file in the app's Documents folder). Never leaves the device.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("history.json")
    }

    func add(direction: Direction, source: String, translation: String, date: Date = Date()) {
        entries.append(HistoryEntry(
            id: UUID(), date: date, direction: direction, source: source, translation: translation
        ))
        save()
    }

    func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
