# Decisions

| ID | Question | Decision | Rationale | Source | Date |
|---|---|---|---|---|---|
| D-001 | Có Mac không? | Không, chỉ Windows | Build trên GitHub Actions macOS runner | user | 2026-10-06 |
| D-002 | Cài lên iPhone | Apple ID free + AltStore (ký lại mỗi 7 ngày) | Không tốn $99/năm | user | 2026-10-06 |
| D-003 | Công nghệ | Swift native (SwiftUI) | Ổn định nhất cho background audio | user | 2026-10-06 |
| D-004 | Đổi chiều hội thoại | Bấm nút / AirPods / Back Tap | Offline, đơn giản | user | 2026-10-06 |
| D-005 | Output khi ẩn | TTS vào tai nghe + phụ đề màn hình khoá | | user | 2026-10-06 |
| D-006 | Lịch sử | Lưu local (JSON trong Documents), có xoá từng dòng / xoá hết | | user | 2026-10-06 |
| D-007 | Phụ đề màn hình khoá | Dùng thẻ Now Playing thay vì Live Activity cho v1 | Live Activity cần widget extension → tốn thêm App ID với Apple ID free, rủi ro deadline 8h | auto | 2026-10-06 |
| D-008 | Bộ dịch v1 | Chỉ online: Apple Speech (server) + Google gtx, retry 1 lần. Code Apple Translation offline để sẵn ở `Offline/` cho v2 | iPhone luôn có mạng, ưu tiên ra app nhanh | user | 2026-10-06 |
| D-009 | Tạm dừng ở chế độ ẩn | Giữ micro chạy, chỉ ngừng nhận dạng | iOS không cho bật micro mới khi app đang ở nền → bật lại bằng Back Tap/AirPods cần micro còn giữ | auto | 2026-10-06 |
| D-010 | Deployment target | iOS 17.0 (máy thật chạy iOS 26.6.1) | Phủ rộng, không mất gì | auto | 2026-10-06 |
| D-011 | Phân biệt giọng bạn / người khác | Picovoice Eagle (đăng ký giọng mẫu, chạy trên máy), AccessKey lưu Keychain | iOS không có API speaker-ID; Eagle có SDK iOS | user | 2026-10-06 |
| D-012 | Luồng hội thoại | Bạn nói EN → im lặng · Bạn nói VI → EN phát loa ngoài · Người khác nói EN → VI riêng cho bạn | Yêu cầu của bạn | user | 2026-10-06 |
| D-013 | Nhận biết ngôn ngữ | Chạy song song 2 recognizer vi-VN + en-US, chọn theo tỉ lệ dấu tiếng Việt trong bản vi | Không cần dịch vụ ngoài; Eagle chỉ trả lời "ai", không trả lời "tiếng gì" | auto | 2026-10-06 |
| D-014 | Chưa đăng ký giọng | Đoán theo ngôn ngữ: VI = bạn, EN = người khác | App vẫn dùng được trước khi có AccessKey | auto | 2026-10-06 |
| D-015 | Claude | Dịch VI → EN đơn giản (A2–B1) + gợi ý 3 câu trả lời, chạm để đọc to. Mặc định Haiku 4.5 (nhanh), chọn được Sonnet 5.5. Key người dùng nhập, lưu Keychain; không có key → Google | Yêu cầu "trả lời thông minh hơn" + "từ ngữ đơn giản" | user | 2026-10-06 |
| D-016 | Đầu ra khi không có tai nghe | Mặc định "Áp tai" (loa thoại); tiếng Anh cho người nghe luôn ra loa ngoài, mic tạm tắt lúc phát | Kín đáo cho bạn, rõ cho người nghe | auto | 2026-10-06 |
| D-017 | AirPods bấm 2 lần | Đọc lại câu dịch gần nhất (thay cho "đổi chiều", không còn cần) | Chiều dịch giờ tự động | auto | 2026-10-06 |
| D-018 | Thay Picovoice (bắt buộc email công ty) | C: làm B trước (nút/phím tắt "Tôi nói tiếng Anh", câu EN kế tiếp trong 30s không dịch), A sau (sherpa-onnx speaker embedding, offline, không tài khoản). Gỡ Eagle | Có app dùng ngay; nhận diện tự động cần thử trên máy | user | 2026-10-06 |
| D-019 | Nhận diện giọng tự động (A) | sherpa-onnx 1.13.8 static xcframework + onnxruntime 1.28.2, model 3D-Speaker CAM++ zh_en advanced (28 MB, tải lúc build, pin SHA-256). Đăng ký 20 s → trung bình embedding các đoạn 4 s có tiếng; mỗi câu: cosine với giọng mẫu, ngưỡng mặc định 50%. Hiện "giọng xx%" trên từng câu để chỉnh ngưỡng | Miễn phí, offline, không tài khoản; model huấn luyện zh+en hợp giọng châu Á | auto | 2026-10-06 |
| D-020 | Tên app trên màn hình chính | "Live Dich" (không dấu); tiêu đề trong app vẫn "Live Dịch" | AltServer tạo App ID theo tên app, Apple từ chối ký tự có dấu ("The name for this app is invalid") | auto | 2026-10-07 |
