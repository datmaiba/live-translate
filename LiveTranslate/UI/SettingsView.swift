import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var translator: LiveTranslator
    @Environment(\.dismiss) private var dismiss
    @State private var packStatus = "Đang kiểm tra…"
    @State private var downloading = false

    var body: some View {
        NavigationStack {
            Form {
                outputSection
                translationSection
                hiddenModeSection
                Section("Lịch sử") {
                    Toggle("Lưu lịch sử trên máy", isOn: $translator.saveHistory)
                }
                Section {
                    LabeledContent("Phiên bản", value: appVersion)
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
            .task { await refreshPackStatus() }
        }
    }

    private var outputSection: some View {
        Section {
            Toggle("Đọc bản dịch (giọng nói)", isOn: $translator.speakOutput)
            VStack(alignment: .leading) {
                Text("Tốc độ đọc")
                Slider(
                    value: $translator.speechRate,
                    in: Double(AVSpeechUtteranceMinimumSpeechRate + 0.25)...Double(AVSpeechUtteranceDefaultSpeechRate + 0.15)
                )
            }
            Toggle("Tắt mic khi đang đọc", isOn: $translator.muteWhileSpeaking)
        } header: {
            Text("Đầu ra")
        } footer: {
            Text("""
            Bật "Tắt mic khi đang đọc" để app không tự nghe lại giọng đọc khi dùng loa ngoài. \
            Đeo AirPods có thể tắt để không bỏ lỡ câu nói.
            """)
        }
    }

    private var translationSection: some View {
        Section {
            Picker("Bộ dịch", selection: $translator.engine) {
                ForEach(LiveTranslator.Engine.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if #available(iOS 18.0, *) {
                LabeledContent("Gói offline Việt ⇄ Anh", value: packStatus)
                Button(downloading ? "Đang tải…" : "Tải gói dịch offline") {
                    Task { await downloadPacks() }
                }
                .disabled(downloading)
            } else {
                Text("Dịch offline cần iOS 18 trở lên — đang dùng Google.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Dịch")
        } footer: {
            Text("Apple dịch offline, miễn phí, riêng tư. Nếu Apple chưa sẵn sàng hoặc lỗi, chế độ Tự động chuyển sang Google (cần mạng).")
        }
    }

    private var hiddenModeSection: some View {
        Section("Chế độ ẩn") {
            Text("""
            1. Bấm micro một lần trong app → khoá màn hình / mở app khác, app vẫn dịch.
            2. Bản dịch mới nhất hiện ở thẻ phát nhạc trên màn hình khoá.
            3. AirPods: bấm 1 lần = bật/tạm dừng, bấm 2 lần (next) = đổi chiều.
            4. Gõ mặt lưng: app Phím tắt › + › thêm tác vụ "Bật/Tắt dịch" của Live Dịch → lưu. \
            Rồi Cài đặt › Trợ năng › Cảm ứng › Chạm vào mặt sau › Chạm hai lần › chọn phím tắt đó.
            5. Chấm cam (micro) luôn hiện khi app nghe — iOS bắt buộc, không ẩn được.
            """)
            .font(.footnote)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func refreshPackStatus() async {
        if #available(iOS 18.0, *) {
            packStatus = await translator.appleBridge.statusText()
        }
    }

    private func downloadPacks() async {
        guard #available(iOS 18.0, *) else { return }
        downloading = true
        defer { downloading = false }
        do {
            try await translator.appleBridge.prepare(direction: .viToEn)
            try await translator.appleBridge.prepare(direction: .enToVi)
        } catch {
            translator.errorMessage = "Tải gói offline lỗi: \(error.localizedDescription)"
        }
        await refreshPackStatus()
    }
}
