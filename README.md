# Live Dịch — dịch trực tiếp Việt ⇄ Anh cho iPhone

App cá nhân, cài bằng AltStore (không qua App Store). Dịch hội thoại liên tục, chạy được khi khoá màn hình hoặc đang dùng app khác.

## Tính năng

- Nghe micro (iPhone hoặc AirPods) → nhận dạng giọng nói → dịch → đọc bản dịch vào tai nghe + hiện phụ đề.
- Bản v1 dịch online (Google), cần mạng. Bản offline (Apple Translation) để ở `Offline/`, sẽ bật ở v2.
- **Chế độ ẩn:** chạy nền, bản dịch hiện trên thẻ phát nhạc ở màn hình khoá.
  - AirPods: bấm 1 lần = bật/tạm dừng · bấm 2 lần = đổi chiều dịch.
  - Gõ 2 lần mặt lưng iPhone (Back Tap) = bật/tạm dừng.
- Lịch sử lưu trên máy, xoá từng dòng (vuốt) hoặc xoá hết.

## Build

Không cần Mac: mỗi lần push lên `main`, GitHub Actions (`.github/workflows/build.yml`) sẽ lint, chạy unit test, build `LiveTranslate.ipa` chưa ký và đăng lên **Releases**.

Build trên Mac: `brew install xcodegen && xcodegen generate && open LiveTranslate.xcodeproj`.

## Cài lên iPhone (Windows + AltStore)

1. Cài AltStore theo https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
2. Trên iPhone, mở Safari vào trang Releases của repo → tải `LiveTranslate.ipa`.
3. Mở AltStore → tab **My Apps** → nút **+** → chọn file `.ipa` vừa tải.
4. Mở app → cho phép Micro + Nhận dạng lời nói.
5. **Mỗi 7 ngày** app hết hạn: để PC bật AltServer cùng Wi-Fi, mở AltStore → **Refresh All**.

## Cài Back Tap

1. App **Phím tắt** → **+** → Thêm tác vụ → tìm "Live Dịch" → chọn **Bật/Tắt dịch** → lưu.
2. **Cài đặt › Trợ năng › Cảm ứng › Chạm vào mặt sau › Chạm hai lần** → chọn phím tắt vừa tạo.

## Giới hạn của iOS

- Chấm cam micro luôn hiện khi app đang nghe (quyền riêng tư của iOS, không tắt được).
- Lần đầu phải mở app và bấm micro. Sau đó khi app ở nền, Back Tap/AirPods chỉ tạm dừng/bật lại được, không khởi động mới được micro. Bấm ⏹ "Dừng hẳn" để tắt hoàn toàn.
- Dùng loa ngoài thì nên bật "Tắt mic khi đang đọc" để app không nghe lại giọng đọc của chính nó.
