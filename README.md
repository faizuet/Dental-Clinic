# Nabi Dental Clinic

Owner-operated desktop app for **Nabi Dental Clinic**. It keeps clinic treatments, fees, and expenses on the clinic laptop, and a separate **Home** module for household grocery spending.

The project is a local monorepo: a FastAPI + PostgreSQL API and a Flutter Windows client. Both run with Docker on this computer. There is no cloud host, no staff logins, and no public patient portal.

---

## Product

The clinic owner signs in once, then switches between **Clinic** and **Home** in the sidebar. The two domains share the same design and offline cache. Their records, totals, and reports stay independent.

| Domain | What it manages |
| ------ | --------------- |
| **Clinic** | Patients, treatments, visit history, X-rays, clinic expenses, income / profit reports |
| **Home** | Grocery expenses, monthly budget, remaining amount, household reports |

It does **not** include appointments, staff rosters, multiple clinics, Construction, or cloud deployment.

---

## Clinic

- Patient records with Pakistani mobile numbers (`03xxxxxxxxx`)
- Official treatment catalog (15 treatments), with extra clinical fields only when that treatment needs them
- Visit history that never overwrites an earlier visit
- Treatment fee, notes, serial number, and up to eight X-ray images per visit
- Clinic expenses by category (Lab Charges, Materials, Equipment, Salaries, Rent, Utilities, Other)
- Dashboard totals for income, expenses, and profit
- Inclusive date-range reports with PDF and Excel export
- Individual visit PDF, including X-rays when files are present

**Treatment flow**

```
Patient (name + phone)
  → Main treatment
  → Sub-treatment when required
  → Clinical details for that treatment only
  → Optional X-rays
  → Fee and notes
  → Save as a new historical visit
```

Income totals use the stored fee. Quantity is not multiplied into clinic income.

**Official treatments:** Check Up / Consultation, Simple Extraction, Surgical Extraction, Root Canal Treatment (RCT), Obturation (RCT), Temporary Filling, Permanent Filling, Composite Filling, Scaling, Porcelain Bridge, Zirconia Crown, Braces Fresh, Braces Visits, Braces Retainer, Dental Gems.

---

## Home

- Same dashboard, cards, colors, and navigation style as Clinic
- Grocery expense form with a fixed 34-category list
- Monthly budget, remaining amount, and over-budget state
- History and reports by category, independent of clinic finance

**Grocery categories**

1. Fresh Vegetables
2. Fruits
3. Beef / Mutton
4. Chicken
5. Eggs
6. Daalain
7. Milk / Yogurt
8. Butter Cheese
9. Bread Rusk
10. Honey / Jam
11. Frozen Items
12. Atta White
13. Chawal
14. Sugar
15. Cooking Oil
16. Tea
17. Masaly cooking
18. Ketchup, Mayo, Sauces
19. Dry Fruits
20. Cold drinks
21. Shampoo, Conditioners
22. Soap Body wash
23. Face wash
24. Toothpaste toothbrush
25. Hair Oil
26. Bathroom Accessories
27. Air freshener
28. Tissue
29. Washing Surf
30. Harpic
31. Pheyl
32. Mortien
33. Mosquito spray
34. Hygiene Items

---

## Shared

- Email / password sign-in (JWT access token 20 minutes, refresh token 30 days)
- First sign-in requires a password change
- Offline SQLite cache with sync when the local API is reachable
- Conflict review in Settings if a queued change cannot apply
- Profile photo and password change
- Catalog maintenance for treatments, clinic expenses, and home groceries
- Local backup and restore of the database plus X-rays (zip on this laptop or a USB drive)

---

## Stack

| Layer | Stack |
| ----- | ----- |
| API | Python 3.12, FastAPI, Pydantic v2, Uvicorn |
| Data | PostgreSQL 16, SQLAlchemy 2 (async + asyncpg), Alembic |
| Auth | JWT (HS256), Argon2 password hashes |
| Files | Pillow; avatars and X-rays on local disk |
| Exports | ReportLab (PDF), openpyxl (Excel) |
| App | Flutter 3, Riverpod, go_router, Dio, sqflite |
| Runtime | Docker Compose (API `8001`, Postgres `5433`) |

Currency defaults to **PKR**. Dates use the clinic timezone (`Asia/Karachi`).

---

## Layout

```
nabi-dental-backend/     FastAPI service, migrations, backup scripts, pytest
nabi_dental_app/         Flutter desktop client
```

```
Clinic
  ├── Users
  ├── Patients
  ├── Treatment categories → Treatments → Visits → X-ray files
  └── Clinic expense categories → Clinic expenses

User
  ├── Home grocery categories → Home expenses
  └── Home budgets (year + month)
```

Clinical details are stored as JSON on the visit (`details`). X-rays are files on disk, not image blobs in the database.

---

## Setup

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/) and the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```powershell
# API + database
cd nabi-dental-backend
copy .env.example .env
docker compose up --build

# Desktop app (second terminal)
cd nabi_dental_app
flutter pub get
flutter run -d windows
```

On first start the API container runs migrations, seeds the owner account, and writes a unique `JWT_SECRET_KEY` into `.env`. Do not commit `.env`.

| | |
| --- | --- |
| API | http://127.0.0.1:8001 |
| Docs | http://127.0.0.1:8001/docs |
| Postgres (host) | port `5433` |
| Seed email | `owner@example.com` |
| Seed password | `ChangeMeNow!1` (must be changed on first sign-in) |

The desktop app uses `http://127.0.0.1:8001` unless you pass `--dart-define=API_BASE_URL=...`. After the images are on the laptop, clinic work does not need the public internet.

---

## Backup

Clinic records live in the Docker Postgres volume. X-rays and the profile photo live in the uploads volume. Nothing is copied off this computer unless you save a backup.

1. **Settings → Save clinic backup**
2. Choose a folder, preferably a USB drive
3. Keep that zip off the clinic laptop

**Settings → Restore from backup** replaces patients, treatments, fees, expenses, and X-rays on this computer. Sync waiting changes first. Sign in again after restore.

PowerShell fallback:

```powershell
cd nabi-dental-backend
.\scripts\backup.ps1 -OutputDir E:\ClinicBackups
.\scripts\restore.ps1 -ZipPath E:\ClinicBackups\nabi-dental-backup-2026-11-13-0900.zip
```

The restore script asks you to type `RESTORE`. The zip contains `manifest.json`, a Postgres dump, and the `uploads` folder. It does not include `.env` or passwords in plain text.

---

## Reports

Reports use inclusive `from_date` / `to_date`. The app sends today, the current month, the current year, or a custom range.

| Report | Contents |
| ------ | -------- |
| Clinic PDF / Excel | Treatment rows, clinic expenses, income / expense / profit totals |
| Home PDF / Excel | Grocery spend by category, budget, remaining |
| Visit PDF | One treatment, with X-rays when files are present |

A range with no rows shows an empty report, not a fake total. Exports need the local API. If Docker is down, creates and edits stay in SQLite until the API is back.

Profile photos: JPG, PNG, or WebP, at most 2 MB.  
X-rays: same formats, at most 5 MB, 64–8192 px.

---

## API

Base path `/api/v1`. Health: `GET /health`. Database: `GET /ready`.

| Group | Role |
| ----- | ---- |
| `/auth` | Login, refresh, logout, current user, password change |
| `/patients` | Patients and their visits |
| `/treatment-categories`, `/treatments` | Clinic treatment catalog |
| `/treatment-transactions` | Visits, X-ray upload, visit PDF |
| `/clinic-expense-categories`, `/clinic-expenses` | Clinic spending |
| `/home-expense-categories`, `/home-expenses`, `/home-budgets` | Home grocery spending |
| `/dashboard` | Clinic and home period totals |
| `/reports` | JSON plus `/export?format=pdf\|xlsx` for clinic and home |
| `/settings` | Profile, avatar, backup export / restore |
| `/sync` | Bootstrap, push, and pull for the Flutter cache |

Important `.env` values (see `.env.example`):

| Name | Purpose |
| ---- | ------- |
| `DATABASE_URL` | Postgres connection |
| `JWT_SECRET_KEY` | Token signing key (generated on first start) |
| `DEFAULT_CURRENCY` / `DEFAULT_TIMEZONE` | PKR / `Asia/Karachi` |
| `DEFAULT_HOME_BUDGET` | Monthly home budget if no override is set |
| `OWNER_EMAIL` / `OWNER_PASSWORD` | Seed owner |

---

## Tests

API tests use database `nabi_dental_test` on port `5433`, never the live clinic database.

```powershell
cd nabi-dental-backend
pytest

cd nabi_dental_app
flutter test
```
