# Nabi Dental Clinic App

Flutter client for the Nabi Dental Clinic finance API.

## Prerequisites

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and make sure `flutter` is on your PATH.

## First-time setup

From this folder:

```bash
flutter create . --project-name nabi_dental_app --org com.nabidental
flutter pub get
```

`flutter create .` generates the Android and iOS platform folders without overwriting `lib/`.

Add these Android permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

On iOS, add Face ID / Touch ID usage text in `ios/Runner/Info.plist`:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Unlock Nabi Dental with Face ID.</string>
```

## Run

The API is on port **8001**. Android emulators must use `10.0.2.2` instead of `localhost`.

```bash
# Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001

# Windows / Chrome / iOS simulator
flutter run --dart-define=API_BASE_URL=http://localhost:8001
```

## Dev login

- Email: `owner@example.com`
- Password: `ChangeMeNow!1`

## Phase 9

Clinic and home finance screens use the local database as the source of truth. The app refreshes from the API when online, queues mutations when offline, and exports PDF/Excel online only.

Conflict review and retry sync live under Settings. Store builds remain a later release step.

