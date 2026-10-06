import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var translator: LiveTranslator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                outputSection
                claudeSection
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
        }
    }

    private var voiceSection: some View {
        Section {
            Text(translator.speakerStatus).font(.footnote)
        } header: {
            Text("Phân biệt giọng của bạn")
        } footer: {
            Text("""
            App đoán theo ngôn ngữ: tiếng Việt = bạn (dịch sang tiếng Anh, phát loa), tiếng Anh = người khác \
            (dịch cho bạn). Trước khi BẠN nói tiếng Anh, bấm "🙋 Tôi nói tiếng Anh" trên màn hình chính \
            hoặc dùng phím tắt "Tôi nói tiếng Anh" (gắn vào gõ mặt lưng 3 lần) — câu tiếng Anh kế tiếp \
            trong 30 giây sẽ không bị dịch. Nhận diện giọng tự động sẽ có ở bản sau.
            """)
        }
    }

    private var outputSection: some View {
        Section {
            Toggle("Phát tiếng Anh ra loa cho người nghe", isOn: $translator.speakForOthers)
            Toggle("Đọc bản dịch tiếng Việt cho tôi", isOn: $translator.speakForMe)
            Picker("Khi không đeo tai nghe", selection: $translator.privateOutput) {
                ForEach(PrivateOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            VStack(alignment: .leading) {
                Text("Tốc độ đọc")
                Slider(
                    value: $translator.speechRate,
                    in: Double(AVSpeechUtteranceMinimumSpeechRate + 0.25)...Double(AVSpeechUtteranceDefaultSpeechRate + 0.15)
                )
            }
            Toggle("Tắt mic khi đang đọc cho tôi", isOn: $translator.muteWhileSpeaking)
        } header: {
            Text("Âm thanh")
        } footer: {
            Text("""
            Tiếng Anh cho người nghe luôn phát ra loa ngoài (mic tự tắt lúc đó để app không nghe lại chính nó). \
            Bản dịch cho bạn đi vào tai nghe nếu có; nếu không thì theo lựa chọn ở trên — "Áp tai" là áp iPhone lên tai như nghe điện thoại.
            """)
        }
    }

    private var claudeSection: some View {
        Section {
            SecureField("Claude API key (sk-ant-…)", text: $translator.claudeKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Model", selection: $translator.claudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            Toggle("Gợi ý câu trả lời", isOn: $translator.suggestReplies)
        } header: {
            Text("Claude (trả lời thông minh)")
        } footer: {
            Text("""
            Có key: câu tiếng Việt của bạn được Claude dịch sang tiếng Anh đơn giản, thông dụng, \
            và mỗi khi người khác nói, Claude gợi ý 3 câu trả lời ngắn. Không có key: dùng Google. \
            Lấy key tại console.anthropic.com (tính phí theo lượng dùng). Key chỉ lưu trong Keychain của máy.
            """)
        }
    }

    private var hiddenModeSection: some View {
        Section("Chế độ ẩn") {
            Text("""
            1. Bấm micro một lần trong app → khoá màn hình / mở app khác, app vẫn chạy.
            2. Câu dịch mới nhất hiện ở thẻ phát nhạc trên màn hình khoá.
            3. AirPods: bấm 1 lần = bật/tạm dừng, bấm 2 lần = đọc lại câu dịch.
            4. Gõ mặt lưng: app Phím tắt › + › thêm tác vụ "Bật/Tắt dịch" của Live Dịch → lưu. \
            Rồi Cài đặt › Trợ năng › Cảm ứng › Chạm vào mặt sau › Chạm hai lần › chọn phím tắt đó.
            5. Tương tự, gắn phím tắt "Tôi nói tiếng Anh" vào Chạm ba lần — gõ trước khi bạn nói tiếng Anh.
            6. Chấm cam (micro) luôn hiện khi app nghe — iOS bắt buộc, không ẩn được.
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
}
