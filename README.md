# Nabi Dental Clinic

Private finance and treatment records app for a single dental clinic owner. It tracks clinic income and expenses, and it keeps patient treatment history with optional X-rays.

The project is a monorepo: a FastAPI + PostgreSQL API and a Flutter desktop client. Both run on the clinic laptop with Docker. There is no cloud host.

## Contents

- [What it does](#what-it-does)
- [Key features](#key-features)
- [How the app works](#how-the-app-works)
- [Technology](#technology)
- [Project layout](#project-layout)
- [Data model](#data-model)
- [API groups](#api-groups)
- [Setup](#setup)
- [Environment variables](#environment-variables)
- [Running the apps](#running-the-apps)
- [Backup and restore](#backup-and-restore)
- [Reports and files](#reports-and-files)
- [Screenshots](#screenshots)
- [Tests](#tests)
- [Later work](#later-work)

## What it does

Clinic owners usually keep treatment fees and clinic bills in notebooks or spreadsheets. This app keeps those records on the clinic laptop, with email/password sign-in and a dated treatment history per patient.

It is a single-clinic, owner-operated tool. It does not manage staff rosters, appointments, multiple clinics, or public patient portals. It does not deploy to Railway or any other cloud host.

## Key features

**Clinic**

- Treatment income with patient name, phone, automatic serial number, date, fee, and notes
- Dynamic visit form: main treatment, then sub-treatment when needed (for example Prosthetic → Crown / Bridge / denture, Periodontal → Scaling)
- Clinical details that match the selected treatment (tooth, canals, material, arch, and similar fields)
- Up to eight X-ray images per visit (gallery or camera), stored as files and linked to that visit
- Clinic expense entry by category
- Treatment history that does not overwrite earlier visits
- Clinic dashboard totals: income, expenses, profit

**Home**

- Home expense entry by category
- Monthly budget and remaining amount
- Home dashboard and reports

**Construction**

- Material catalog (category, unit)
- Purchase entry: quantity and unit price; the server computes `amount = quantity × unit price`
- Optional supplier and notes
- Construction dashboard and reports

**Shared**

- Email/password login, JWT access token (20 minutes) and refresh token (30 days)
- Offline-first Flutter cache (SQLite) with sync when the API is reachable
- Conflict review under Settings when a queued change cannot apply
- Profile photo and password change
- Catalog maintenance for treatments and expense categories
- Date-range reports (daily, monthly, yearly, or a custom inclusive start/end)
- PDF and Excel export; PDFs save to Downloads on Android
- Individual treatment PDF from a visit record
- Local backup and restore of the database plus X-rays (zip on this laptop or a USB drive)

## How the app works

1. Start Docker Compose, then open the Flutter desktop app.
2. Sign in with the clinic owner email and password.
3. Use the clinic dashboard to add treatments, expenses, history, and reports.
4. Settings covers profile, catalogs, backup and restore, password change, sync conflicts, and sign-out.

### Dental treatment flow

```
Patient (name + phone)
  → Main treatment
  → Sub-treatment when required
  → Clinical details for that treatment only
  → Optional X-ray images
  → Fee and notes
  → Save (new historical visit)
  → History / visit detail / treatment PDF
```

Examples: RCT asks for tooth, canals, and length. Crown asks for tooth and material. Bridge allows several teeth. Scaling stays short (area + fee).

Clinic income totals use the stored fee (`SUM(amount)`). Quantity is not multiplied into income.

### Finance and reporting

| Module        | What is tracked                         | Report export                         |
| ------------- | --------------------------------------- | ------------------------------------- |
| Clinic        | Treatment fees and clinic expenses      | PDF / Excel, inclusive date range     |
| Home          | Expenses vs monthly budget              | PDF / Excel, inclusive date range     |
| Construction  | Material purchases and supplier spend   | PDF / Excel, inclusive date range     |

Custom range uses a start-and-end calendar. Both dates are included. A period with no rows shows that clearly in the PDF instead of a fake total.

## Technology

| Layer    | Stack |
| -------- | ----- |
| API      | Python 3.12, FastAPI, Pydantic v2, Uvicorn |
| Data     | PostgreSQL 16, SQLAlchemy 2 (async + asyncpg), Alembic |
| Auth     | JWT (HS256), Argon2 password hashes |
| Exports  | ReportLab (PDF), openpyxl (Excel) |
| Images   | Pillow; files on local disk under `UPLOAD_DIR` |
| App      | Flutter 3 (Dart SDK `>=3.5.0 <4.0.0`) |
| App libs | Riverpod, go_router, Dio, sqflite, flutter_secure_storage, image_picker |
| Local API| Docker Compose (API on host port 8001, Postgres on 5433) |

Currency defaults to PKR. Dates use the clinic timezone (`Asia/Karachi` by default).

## Project layout

```
nabi-dental-backend/          API
  app/api/v1/endpoints/       HTTP routes
  app/models/                 SQLAlchemy tables
  app/schemas/                Request/response models
  app/services/               Business rules
  app/repositories/           Queries
  app/exports/                PDF and Excel
  alembic/versions/           Migrations
  scripts/                    Local backup and restore PowerShell helpers
  tests/                      Pytest

nabi_dental_app/              Flutter client
  lib/app/                    Theme, router
  lib/core/                   API, auth, SQLite, export, dental helpers
  lib/features/               Screens by module
```

## Data model

```
Clinic
  ├── Users
  ├── Patients
  ├── Treatment categories → Treatments → Treatment transactions → X-ray attachments
  └── Clinic expense categories → Clinic expenses

User
  ├── Home expense categories → Home expenses
  ├── Home budgets (year + month)
  └── Construction categories → Materials → Purchases
```

Treatment-specific clinical fields live in JSON on the treatment transaction (`details`), not as a wide set of nullable columns. X-rays are file paths on disk, not image blobs in the transaction row.

Existing treatment rows keep their fee so finance totals stay valid after the treatment redesign.

## API groups

Base path: `/api/v1`. Interactive docs: `/docs`. Health: `GET /health`. Database readiness: `GET /ready`.

| Group | Role |
| ----- | ---- |
| `/auth` | Login, refresh, logout, logout-all, current user, password change |
| `/patients` | Patient list, create, update, delete, visits for one patient |
| `/treatment-categories`, `/treatments` | Clinic treatment catalog |
| `/treatment-transactions` | Visits, batch create, X-ray upload, visit PDF |
| `/clinic-expense-categories`, `/clinic-expenses` | Clinic spending |
| `/home-expense-categories`, `/home-expenses`, `/home-budgets` | Home spending and budget |
| `/construction-material-categories`, `/construction-materials`, `/construction-purchases` | Construction catalog and purchases |
| `/dashboard` | Clinic and home period totals |
| `/reports` | JSON reports plus `/export?format=pdf\|xlsx` for clinic, home, and construction |
| `/settings` | Clinic/profile settings, avatar, backup export/restore |
| `/sync` | Bootstrap, push, and pull for the Flutter cache |

## Setup

### Backend (Docker, recommended)

Requires Docker Desktop.

```powershell
cd nabi-dental-backend
copy .env.example .env
docker compose up --build
```

On first start the container runs `alembic upgrade head` and seeds the owner account.

- API: `http://127.0.0.1:8001`
- Docs: `http://127.0.0.1:8001/docs`
- Postgres on the host: port `5433` (the app container talks to `db:5432`)

### Backend (local Python)

PostgreSQL 16 must be running. Point `DATABASE_URL` at it (the example uses `localhost:5433`).

```powershell
cd nabi-dental-backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
alembic upgrade head
python -m app.db.seed
uvicorn app.main:app --reload --port 8000
```

If you run Uvicorn on 8000, point Flutter at that port instead of 8001.

### Flutter

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```powershell
cd nabi_dental_app
flutter pub get
flutter run -d windows
```

Development seed login (change this on first sign-in; the app will require it):

- Email: `owner@example.com`
- Password: `ChangeMeNow!1`

The API replaces an example `JWT_SECRET_KEY` with a unique value in `.env` on first start. Existing sessions then need a fresh sign-in.

Do not commit `.env`. Copy `.env.example` instead.

## Environment variables

Set these in `nabi-dental-backend/.env`. Values below are local laptop examples.

| Name | Purpose | Example |
| ---- | ------- | ------- |
| `APP_NAME` | API title | `Nabi Dental Clinic API` |
| `APP_ENV` | Runtime mode | `development` |
| `DEBUG` | Verbose errors | `true` |
| `DATABASE_URL` | Postgres URL (`postgres://` is accepted and normalized) | `postgresql+asyncpg://postgres:postgres@localhost:5433/nabi_dental` |
| `PORT` | Listen port inside the container | `8000` |
| `JWT_SECRET_KEY` | Token signing key | a long random string |
| `ACCESS_TOKEN_MINUTES` | Access token lifetime | `20` |
| `REFRESH_TOKEN_DAYS` | Refresh token lifetime | `30` |
| `CORS_ORIGINS` | Extra allowed origins (comma-separated) | empty on a laptop |
| `DEFAULT_CLINIC_NAME` | Seed clinic name | `Nabi Dental Clinic` |
| `DEFAULT_CURRENCY` | Money code | `PKR` |
| `DEFAULT_TIMEZONE` | IANA timezone | `Asia/Karachi` |
| `DEFAULT_HOME_BUDGET` | Default monthly home budget | `30000.00` |
| `OWNER_EMAIL` / `OWNER_PASSWORD` / `OWNER_FULL_NAME` | Seed owner | see `.env.example` |
| `UPLOAD_DIR` | Avatar and X-ray files | `uploads` |
| `AVATAR_MAX_BYTES` | Profile photo size cap | `2000000` |
| `XRAY_MAX_BYTES` | X-ray size cap | `5000000` |

The Flutter desktop app uses `http://127.0.0.1:8001` unless you pass `--dart-define=API_BASE_URL=...`.

## Running the apps

```powershell
# API + database (local Docker)
cd nabi-dental-backend
copy .env.example .env
docker compose up --build

# Flutter desktop on this laptop
cd nabi_dental_app
flutter run -d windows
```

The API listens on `http://127.0.0.1:8001`. The desktop app uses that address by default. After the Docker images are on the laptop, clinic work does not need the public internet.

Rebuild the API image once so it includes PostgreSQL client tools (`pg_dump` / `pg_restore`):

```powershell
cd nabi-dental-backend
docker compose up --build
```

## Backup and restore

Clinic records live in the Docker Postgres volume. X-rays and the profile photo live in the uploads volume. Neither is copied anywhere else unless you save a backup.

**From the desktop app (preferred)**

1. Open **Settings → Save clinic backup**.
2. Choose a folder, preferably a USB drive.
3. Keep that zip off the clinic laptop.

Restore is **Settings → Restore from backup**. It replaces all patients, treatments, fees, expenses, and X-rays on this computer. Sync any waiting changes first. After restore, the app reloads from the restored database.

The dashboard reminds you if no backup has been saved on this computer, or if the last save is more than seven days old.

**From PowerShell if the app cannot export**

```powershell
cd nabi-dental-backend
.\scripts\backup.ps1
.\scripts\backup.ps1 -OutputDir E:\ClinicBackups
.\scripts\restore.ps1 -ZipPath E:\ClinicBackups\nabi-dental-backup-2026-11-13-0900.zip
```

The restore script asks you to type `RESTORE`. The zip contains `manifest.json`, a Postgres custom dump, and the `uploads` folder. It does not include `.env` or passwords in plain text. Sign in after moving the backup to another laptop.

## Reports and files

Reports accept `from_date` and `to_date` (inclusive calendar dates). The Flutter report screen sends the selected period: today, current month, current year, or a custom range.

- Clinic PDF/Excel: treatment rows (serial, patient, dates, treatment, details, fee), expense rows, and totals
- Home PDF/Excel: expenses, budget, remaining
- Construction PDF/Excel: materials, quantities, suppliers, purchase history
- Visit PDF: one treatment, including X-rays when files are present

Profile photos: JPG, PNG, or WebP, at most 2 MB, stored under `uploads/avatars/`.  
Treatment X-rays: same formats, at most 5 MB, 64–8192 px, stored under `uploads/xrays/{clinic}/{visit}/`. Empty or invalid files are rejected with a short message.

PDF and Excel exports need the local API running. If the API is down, the desktop app keeps queued creates and edits in SQLite until Docker is started again.

### Mobile UX that is implemented

- Compact layout and a max content width on larger screens
- Hardware/system back: exit confirmation on the module home, discard confirmation on dirty forms
- Shared confirmation dialogs for delete, sign-out, and similar actions
- Downloads + open for PDF/Excel on Android

## Screenshots

Add images under `docs/screenshots/` and link them here.

| Screen | File |
| ------ | ---- |
| Module selection | `docs/screenshots/modules.png` |
| Clinic dashboard | `docs/screenshots/clinic.png` |
| New treatment | `docs/screenshots/treatment.png` |
| Reports | `docs/screenshots/reports.png` |

## Tests

```powershell
# API (Postgres on localhost:5433, or TEST_DATABASE_URL)
cd nabi-dental-backend
pytest

# Flutter unit tests
cd nabi_dental_app
flutter test
```

## Later work

- Windows release signing for a clinic installer
