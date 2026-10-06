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
| D-008 | Bộ dịch | Tự động: Apple Translation (offline, iOS 18+) → fallback Google gtx endpoint | Miễn phí, chạy được cả khi Apple chưa tải gói | auto | 2026-10-06 |
| D-009 | Tạm dừng ở chế độ ẩn | Giữ micro chạy, chỉ ngừng nhận dạng | iOS không cho bật micro mới khi app đang ở nền → bật lại bằng Back Tap/AirPods cần micro còn giữ | auto | 2026-10-06 |
| D-010 | Deployment target | iOS 17.0 | Phủ iPhone 11; Apple Translation chỉ bật khi iOS 18+ | auto | 2026-10-06 |
