import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var translator: LiveTranslator
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                directionBar
                transcript
                controls
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Live Dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView(history: translator.history)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(translator)
            }
        }
        .background(translationHost)
    }

    @ViewBuilder
    private var translationHost: some View {
        if #available(iOS 18.0, *) {
            TranslationHost(bridge: translator.appleBridge)
        }
    }

    // MARK: - Sections

    private var directionBar: some View {
        Button {
            translator.swapDirection()
        } label: {
            HStack(spacing: 14) {
                langChip(translator.direction.source)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                langChip(translator.direction.target)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
    }

    private func langChip(_ lang: Lang) -> some View {
        HStack(spacing: 6) {
            Text(lang.flag)
            Text(lang.name).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.chip))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if translator.lines.isEmpty && translator.partial.isEmpty {
                        emptyState
                    }
                    ForEach(translator.lines) { line in
                        LineView(line: line).id(line.id)
                    }
                    if !translator.partial.isEmpty {
                        Text(translator.partial)
                            .font(.body.italic())
                            .foregroundStyle(.secondary)
                            .id("partial")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: translator.lines) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: translator.partial) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bấm nút micro để bắt đầu.")
                .font(.headline)
            Text("""
            • Khoá màn hình hoặc mở app khác vẫn dịch tiếp.
            • Bản dịch hiện trên màn hình khoá và đọc vào tai nghe.
            • AirPods: bấm 1 lần = bật/tạm dừng, bấm 2 lần = đổi chiều.
            • Gõ 2 lần mặt lưng iPhone để bật/tắt (cài trong ⚙️).
            """)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let error = translator.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            HStack(spacing: 28) {
                Button {
                    translator.clearScreen()
                } label: {
                    Image(systemName: "trash").font(.title3)
                }
                .disabled(translator.lines.isEmpty)

                Button {
                    translator.toggle()
                } label: {
                    Image(systemName: mainIcon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(mainColor))
                        .shadow(color: mainColor.opacity(0.5), radius: translator.state == .listening ? 14 : 0)
                }

                Button {
                    translator.stopCompletely()
                } label: {
                    Image(systemName: "stop.circle").font(.title2)
                }
                .disabled(translator.state == .idle)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var mainIcon: String {
        switch translator.state {
        case .idle: return "mic.fill"
        case .listening: return "pause.fill"
        case .paused: return "play.fill"
        }
    }

    private var mainColor: Color {
        switch translator.state {
        case .idle: return Theme.accent
        case .listening: return .red
        case .paused: return .orange
        }
    }

    private var statusText: String {
        switch translator.state {
        case .idle: return "Chưa bật"
        case .listening: return "Đang nghe \(translator.direction.source.name)…"
        case .paused: return "Tạm dừng — micro vẫn giữ để bật lại nhanh"
        }
    }
}

private struct LineView: View {
    let line: LiveTranslator.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.source)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(line.translation)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            if !line.engine.isEmpty {
                Text(line.engine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Theme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let chip = Color(red: 0.16, green: 0.18, blue: 0.22)
    static let accent = Color(red: 0.20, green: 0.62, blue: 1.0)
}
