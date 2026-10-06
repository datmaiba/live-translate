import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var translator: LiveTranslator
    @Environment(\.dismiss) private var dismiss
    @State private var showEnrollment = false

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
            .sheet(isPresented: $showEnrollment) {
                EnrollmentView()
            }
            .onChange(of: showEnrollment) {
                if !showEnrollment { translator.reloadSpeakerID() }
            }
        }
    }

    private var voiceSection: some View {
        Section {
            Text(translator.speakerStatus).font(.footnote)
            Button(translator.hasVoiceProfile ? "Đăng ký lại giọng của tôi" : "Đăng ký giọng của tôi") {
                translator.stopCompletely()
                showEnrollment = true
            }
            if translator.hasVoiceProfile {
                Button("Xoá giọng đã lưu", role: .destructive) { translator.deleteVoiceProfile() }
            }
            VStack(alignment: .leading) {
                Text("Ngưỡng là giọng bạn: \(Int(translator.ownerThreshold * 100))%")
                Slider(value: $translator.ownerThreshold, in: 0.2...0.9, step: 0.05)
            }
        } header: {
            Text("Phân biệt giọng của bạn")
        } footer: {
            Text("""
            Nhận diện chạy ngay trên iPhone, không cần mạng hay tài khoản. Mỗi câu trên màn hình có "giọng xx%": \
            nếu người khác hay bị nhận là bạn → tăng ngưỡng; nếu bạn hay bị nhận là người khác → giảm ngưỡng. \
            Chưa đăng ký giọng thì app đoán theo ngôn ngữ (tiếng Việt = bạn). \
            Nút "🙋 Tôi nói tiếng Anh" luôn dùng được khi cần chắc chắn.
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
            4. Gõ mặt lưng: app Phím tắt › + › thêm tác vụ "Bật/Tắt dịch" của Live Dich → lưu. \
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
