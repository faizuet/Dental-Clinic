# Nabi Dental Clinic (Flutter)

Windows desktop client for the local Nabi Dental Clinic API.

The app has two independent domains, **Clinic** and **Home**, with a shared design and offline cache.

Full product documentation is in the [repository README](../README.md).

## Quick start

Start the local API first (`docker compose up --build` in `nabi-dental-backend`), then:

```powershell
flutter pub get
flutter run -d windows
```

The app talks to `http://127.0.0.1:8001` by default. Override only if you changed the API port:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8001
```
