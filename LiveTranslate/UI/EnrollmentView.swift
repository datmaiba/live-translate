import SwiftUI

struct EnrollmentView: View {
    @StateObject private var enroller = VoiceEnroller()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Ở chỗ yên tĩnh, đọc to và tự nhiên đoạn dưới đây trong khoảng 20 giây. Đọc hết thì đọc lại từ đầu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(Self.script)
                    .font(.body)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.chip))

                ProgressView(value: enroller.progress) {
                    Text("\(Int(enroller.progress * 100))%")
                }
                .tint(enroller.finished ? .green : Theme.accent)

                if enroller.isProcessing {
                    ProgressView()
                }
                if let message = enroller.message {
                    Text(message).font(.footnote)
                }

                if enroller.finished {
                    Button("Xong") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else if !enroller.isRecording && !enroller.isProcessing {
                    Button("Bắt đầu thu giọng") { enroller.start() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
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
        .interactiveDismissDisabled(enroller.isRecording || enroller.isProcessing)
    }

    private static let script = """
    Xin chào, tôi tên là Đạt. Hôm nay trời đẹp và tôi đang thử ứng dụng dịch trực tiếp. \
    Hello, my name is Dat. I live in Vietnam and I like to meet new people. \
    Tôi thường đi làm bằng xe máy, buổi tối tôi đọc sách và học tiếng Anh. \
    Could you please speak a little slower? Thank you very much for your help.
    """
}
