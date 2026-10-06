import SwiftUI

struct EnrollmentView: View {
    let accessKey: String
    @StateObject private var enroller = VoiceEnroller()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Đọc to, tự nhiên đoạn dưới đây (tiếng Việt hoặc tiếng Anh đều được) ở chỗ yên tĩnh cho tới khi đủ 100%.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(Self.script)
                    .font(.body)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.chip))

                ProgressView(value: Double(enroller.progress), total: 100) {
                    Text("\(Int(enroller.progress))%")
                }
                .tint(enroller.finished ? .green : Theme.accent)

                if let message = enroller.message {
                    Text(message).font(.footnote)
                }

                if enroller.finished {
                    Button("Xong") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(enroller.isRecording ? "Đang nghe… bấm để dừng" : "Bắt đầu thu giọng") {
                        if enroller.isRecording {
                            enroller.stop()
                        } else {
                            enroller.start(accessKey: accessKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(enroller.isRecording ? .red : Theme.accent)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Đăng ký giọng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Huỷ") {
                        enroller.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(enroller.isRecording)
    }

    private static let script = """
    Xin chào, tôi tên là Đạt. Hôm nay trời đẹp và tôi đang thử ứng dụng dịch trực tiếp. \
    Hello, my name is Dat. I live in Vietnam and I like to meet new people. \
    Tôi thường đi làm bằng xe máy, buổi tối tôi đọc sách và học tiếng Anh. \
    Could you please speak a little slower? Thank you very much for your help.
    """
}
