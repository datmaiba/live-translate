# Live Dịch — dịch trực tiếp Việt ⇄ Anh cho iPhone

App cá nhân, cài bằng AltStore (không qua App Store). Dịch hội thoại liên tục, chạy được khi khoá màn hình hoặc đang dùng app khác.

## Tính năng

- **Hội thoại tự động** — nhận diện giọng bạn ngay trên máy (sherpa-onnx, không cần mạng/tài khoản); chưa đăng ký giọng thì đoán theo ngôn ngữ:
  - Bạn nói **tiếng Anh** → app im lặng (khi cần chắc chắn: bấm **🙋 Tôi nói tiếng Anh** hoặc gõ mặt lưng 3 lần trước khi nói).
  - Bạn nói **tiếng Việt** → dịch sang tiếng Anh đơn giản (Claude) và **phát ra loa** cho người đối diện.
  - Người khác nói **tiếng Anh** → dịch tiếng Việt **cho riêng bạn** (tai nghe / áp tai / chỉ chữ) + Claude **gợi ý 3 câu trả lời**, chạm để app đọc to.
- Không đeo tai nghe vẫn dùng được: chế độ "Áp tai" phát bản dịch qua loa thoại như nghe điện thoại.
- Online: Apple Speech (máy chủ) + Google Translate; Claude nếu có API key. Bản offline để ở `Offline/`.
- **Chế độ ẩn:** chạy nền, câu dịch hiện trên thẻ phát nhạc ở màn hình khoá.
  - AirPods: bấm 1 lần = bật/tạm dừng · bấm 2 lần = đọc lại câu dịch.
  - Gõ 2 lần mặt lưng iPhone (Back Tap) = bật/tạm dừng.
- Lịch sử lưu trên máy, xoá từng dòng (vuốt) hoặc xoá hết.

## Thiết lập lần đầu (trong app › ⚙️)

1. **Đăng ký giọng của tôi**: đọc to đoạn mẫu khoảng 20 giây ở chỗ yên tĩnh.
2. **Claude API key** (tuỳ chọn, để có tiếng Anh đơn giản + gợi ý trả lời): https://console.anthropic.com → API Keys → dán vào ô "Claude API key". Tính phí theo lượng dùng.
3. Gắn phím tắt vào gõ mặt lưng (xem "Cài Back Tap" bên dưới).

## Build

Không cần Mac: mỗi lần push lên `main`, GitHub Actions tải sherpa-onnx + model nhận diện giọng (`scripts/fetch-vendor.sh`, có kiểm SHA-256), (`.github/workflows/build.yml`) sẽ lint, chạy unit test, build `LiveTranslate.ipa` chưa ký và đăng lên **Releases**.

Build trên Mac: `bash scripts/fetch-vendor.sh && brew install xcodegen && xcodegen generate && open LiveTranslate.xcodeproj`.

## Cài lên iPhone (Windows + SideStore — cập nhật từ xa, không cần chung Wi-Fi)

Source (danh sách app cho SideStore/AltStore), CI tự cập nhật sau mỗi build:

```
https://raw.githubusercontent.com/datmaiba/live-translate/altstore/source.json
```

1. iPhone: cài **LocalDevVPN** từ App Store.
2. Windows (đã có iTunes): tải **iloader** tại https://github.com/nab138/iloader/releases → cắm cáp iPhone → mở iloader → đăng nhập Apple ID → chọn iPhone → **Install SideStore (Stable)**.
3. iPhone: Cài đặt › Cài đặt chung › Quản lý VPN & Thiết bị → Apple ID → **Tin cậy**; bật **Chế độ nhà phát triển** nếu chưa bật.
4. Mở **LocalDevVPN** → **Connect**. Mở **SideStore** → đăng nhập cùng Apple ID → **My Apps** → chạm **7 DAYS** cạnh SideStore để làm mới.
5. SideStore → **Sources** → **+** → dán URL source ở trên → mở **Live Dich** → **Install**.
6. Bản mới: SideStore → **My Apps** → **Update** (nhớ bật LocalDevVPN). Gia hạn 7 ngày: **Refresh All** — không cần máy tính.

Cách cũ (AltStore + AltServer trên Windows) vẫn dùng được nhưng cần iPhone và máy tính chung Wi-Fi.

## Cài Back Tap

1. App **Phím tắt** → **+** → Thêm tác vụ → tìm "Live Dich" → chọn **Bật/Tắt dịch** → lưu. Làm thêm một phím tắt **Tôi nói tiếng Anh**.
2. **Cài đặt › Trợ năng › Cảm ứng › Chạm vào mặt sau**: **Chạm hai lần** → "Bật/Tắt dịch", **Chạm ba lần** → "Tôi nói tiếng Anh".

## Giới hạn của iOS

- Chấm cam micro luôn hiện khi app đang nghe (quyền riêng tư của iOS, không tắt được).
- Lần đầu phải mở app và bấm micro. Sau đó khi app ở nền, Back Tap/AirPods chỉ tạm dừng/bật lại được, không khởi động mới được micro. Bấm ⏹ "Dừng hẳn" để tắt hoàn toàn.
- Dùng loa ngoài thì nên bật "Tắt mic khi đang đọc" để app không nghe lại giọng đọc của chính nó.
