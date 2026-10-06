import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private var items: [HistoryEntry] { history.entries.reversed() }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("Chưa có lịch sử", systemImage: "clock")
                } else {
                    List {
                        ForEach(items) { entry in
                            row(entry)
                        }
                        .onDelete { offsets in
                            history.delete(ids: Set(offsets.map { items[$0].id }))
                        }
                    }
                }
            }
            .navigationTitle("Lịch sử")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Xoá hết", role: .destructive) { confirmClear = true }
                        .disabled(items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
            .confirmationDialog("Xoá toàn bộ lịch sử?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Xoá hết", role: .destructive) { history.clear() }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.direction.label).font(.caption.weight(.semibold))
                Spacer()
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.source).font(.subheadline).foregroundStyle(.secondary)
            Text(entry.translation).font(.body)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.translation
            } label: {
                Label("Copy bản dịch", systemImage: "doc.on.doc")
            }
            Button {
                UIPasteboard.general.string = "\(entry.source)\n\(entry.translation)"
            } label: {
                Label("Copy cả hai", systemImage: "doc.on.doc.fill")
            }
        }
    }
}
