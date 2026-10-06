import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var translator: LiveTranslator
    @State private var showHistory = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
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
            .onChange(of: showSettings) {
                if !showSettings { translator.reloadSpeakerID() }
            }
        }
    }

    // MARK: - Sections

    private var statusBar: some View {
        Button {
            showSettings = true
        } label: {
            Text(translator.speakerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if translator.lines.isEmpty && translator.partial.isEmpty {
                        emptyState
                    }
                    ForEach(translator.lines) { line in
                        LineView(line: line) { translator.say($0) }
                            .id(line.id)
                    }
                    if !translator.partial.isEmpty {
                        Text(translator.partial)
                            .font(.body.italic())
                            .foregroundStyle(.secondary)
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
            • Bạn nói tiếng Việt → app nói tiếng Anh ra loa cho người nghe.
            • Bạn nói tiếng Anh → app im lặng.
            • Người khác nói tiếng Anh → app dịch tiếng Việt cho riêng bạn + gợi ý câu trả lời. Chạm gợi ý để app đọc to.
            • Khoá màn hình / mở app khác vẫn chạy. AirPods: bấm 1 lần = bật/tạm dừng, 2 lần = đọc lại.
            • Lần đầu: vào ⚙️ đăng ký giọng của bạn để app phân biệt bạn với người khác.
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
                    .onTapGesture { translator.errorMessage = nil }
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
        case .listening: return "Đang nghe…"
        case .paused: return "Tạm dừng — micro vẫn giữ để bật lại nhanh"
        }
    }
}

private struct LineView: View {
    let line: LiveTranslator.Line
    let onSay: (ReplySuggestion) -> Void

    private var isMe: Bool { line.speaker == .me }

    var body: some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(isMe ? "🧑 Bạn" : "🗣 Người khác")
                Text(line.language.shortLabel)
                if !line.note.isEmpty { Text("· \(line.note)") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(line.source)
                .font(line.translation.isEmpty ? .body : .subheadline)
                .foregroundStyle(line.translation.isEmpty ? .primary : .secondary)

            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isMe ? Theme.accent : .primary)
            }

            if line.loadingSuggestions {
                ProgressView().controlSize(.small)
            }
            ForEach(line.suggestions, id: \.self) { suggestion in
                Button {
                    onSay(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(suggestion.en, systemImage: "speaker.wave.2.fill")
                            .font(.callout.weight(.semibold))
                        Text(suggestion.vi)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.chip))
                }
                .buttonStyle(.plain)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .multilineTextAlignment(isMe ? .trailing : .leading)
    }
}

enum Theme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let chip = Color(red: 0.16, green: 0.18, blue: 0.22)
    static let accent = Color(red: 0.20, green: 0.62, blue: 1.0)
}
