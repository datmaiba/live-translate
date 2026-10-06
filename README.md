# Live Dịch — dịch trực tiếp Việt ⇄ Anh cho iPhone

App cá nhân, cài bằng AltStore (không qua App Store). Dịch hội thoại liên tục, chạy được khi khoá màn hình hoặc đang dùng app khác.

## Tính năng

- **Hội thoại tự động** (nhận diện giọng bạn bằng Picovoice Eagle):
  - Bạn nói **tiếng Anh** → app im lặng.
  - Bạn nói **tiếng Việt** → dịch sang tiếng Anh đơn giản (Claude) và **phát ra loa** cho người đối diện.
  - Người khác nói **tiếng Anh** → dịch tiếng Việt **cho riêng bạn** (tai nghe / áp tai / chỉ chữ) + Claude **gợi ý 3 câu trả lời**, chạm để app đọc to.
- Không đeo tai nghe vẫn dùng được: chế độ "Áp tai" phát bản dịch qua loa thoại như nghe điện thoại.
- Online: Apple Speech (máy chủ) + Google Translate; Claude nếu có API key. Bản offline để ở `Offline/`.
- **Chế độ ẩn:** chạy nền, câu dịch hiện trên thẻ phát nhạc ở màn hình khoá.
  - AirPods: bấm 1 lần = bật/tạm dừng · bấm 2 lần = đọc lại câu dịch.
  - Gõ 2 lần mặt lưng iPhone (Back Tap) = bật/tạm dừng.
- Lịch sử lưu trên máy, xoá từng dòng (vuốt) hoặc xoá hết.

## Thiết lập lần đầu (trong app › ⚙️)

1. **Picovoice AccessKey**: đăng ký tại https://console.picovoice.ai → copy AccessKey → dán vào ô "Picovoice AccessKey".
2. Bấm **Đăng ký giọng của tôi**, đọc to đoạn văn mẫu tới 100% (chỗ yên tĩnh).
3. **Claude API key** (tuỳ chọn, để có tiếng Anh đơn giản + gợi ý trả lời): https://console.anthropic.com → API Keys → dán vào ô "Claude API key". Tính phí theo lượng dùng.

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
