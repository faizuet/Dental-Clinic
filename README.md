# Dental Clinic

Private owner finance app for Nabi Dental Clinic: clinic, home, and construction tracking.

## Folders

- `nabi-dental-backend` — FastAPI + Postgres API
- `nabi_dental_app` — Flutter app

## Local backend

```powershell
cd nabi-dental-backend
copy .env.example .env
docker compose up --build
```

API: `http://127.0.0.1:8001/docs`

## Flutter (USB phone)

```powershell
cd nabi_dental_app
adb reverse tcp:8001 tcp:8001
flutter run -d <device-id> --dart-define=API_BASE_URL=http://127.0.0.1:8001
```

Do not commit `.env`. Use `.env.example` and `.env.production.example`.
