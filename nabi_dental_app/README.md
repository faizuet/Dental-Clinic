# Nabi Dental Clinic (Flutter)

Offline-first Flutter client for the Nabi Dental Clinic API.

Full project documentation is in the [repository README](../README.md).

## Quick start

```powershell
flutter pub get
adb reverse tcp:8001 tcp:8001
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8001
```

If `API_BASE_URL` is omitted, Android emulators use `http://10.0.2.2:8001` and other platforms use `http://localhost:8001`.

Android permissions (internet, camera, photos, biometrics) are already declared in `android/app/src/main/AndroidManifest.xml`.
