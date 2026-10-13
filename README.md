# Tool Soi BCR

Ứng dụng Flutter (đăng nhập / lobby / overlay bảng tính). Có entry-point phụ cho cửa sổ overlay Android (`overlayMain`).

## Yêu cầu

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart **^3.11** theo `pubspec.yaml`)
- Để build Android: Android SDK, **JDK 17** (khớp `android/app/build.gradle.kts`)
- Để build iOS (macOS): Xcode

Kiểm tra môi trường:

```bash
flutter doctor -v
```

## Clone và cài dependency

```bash
git clone <url-repo> tool_forecast
cd tool_forecast
flutter pub get
```

## Cấu hình `.env`

File `.env` ở **thư mục gốc** được load lúc chạy app và khai báo trong `pubspec.yaml` (assets). File thật thường **không** commit (đã ignore).

Sao chép mẫu rồi chỉnh URL / tham số API cho đúng backend:

```bash
# Windows (PowerShell)
copy .env.example .env

# macOS / Linux / Git Bash
cp .env.example .env
```

Mở `.env` và cập nhật các biến (đặc biệt `API_BASE_URL`, `API_PATH_PREFIX` nếu API có tiền tố `/api`).

## Chạy app (debug)

Kết nối thiết bị / mở emulator, sau đó:

```bash
flutter run
```

Chọn entry mặc định (`lib/main.dart`). Overlay dùng isolate riêng trên Android khi bật tính năng overlay (xem code `overlayMain`).

## Build bản phát hành

### Android — APK

```bash
flutter build apk --release
```

File ra tại: `build/app/outputs/flutter-apk/app-release.apk`.

### Android — App Bundle (Google Play)

```bash
flutter build appbundle --release
```

File ra tại: `build/app/outputs/bundle/release/app-release.aab`.

**Ký phát hành:** Trong `android/app/build.gradle.kts`, `release` hiện có thể đang dùng khóa debug để tiện thử. Trước khi đưa lên Play Store cần cấu hình `signingConfigs` và keystore riêng.

### iOS

```bash
flutter build ipa --release
```

(Cần chứng chỉ Apple, team ID, v.v.)

## Ghi chú kỹ thuật

- **Path package:** `flutter_overlay_window` nằm trong `packages/flutter_overlay_window` (dependency `path:` trong `pubspec.yaml`).
- **Phân tích tĩnh:** `dart analyze` hoặc `flutter analyze`.
