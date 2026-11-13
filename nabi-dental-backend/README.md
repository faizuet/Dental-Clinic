# Nabi Dental Clinic API

FastAPI + PostgreSQL service for the local Nabi Dental Clinic desktop app.

Full project documentation is in the [repository README](../README.md).

## Quick start

```powershell
copy .env.example .env
docker compose up --build
```

- API: `http://127.0.0.1:8001`
- Docs: `http://127.0.0.1:8001/docs`

Without Docker: create a venv, `pip install -r requirements.txt`, set `DATABASE_URL`, then `alembic upgrade head`, `python -m app.db.seed`, and `uvicorn app.main:app --reload --port 8000`.

Backup and restore: Settings in the desktop app, or `.\scripts\backup.ps1` / `.\scripts\restore.ps1` from this folder. Rebuild the Compose app image so `pg_dump` is available.

## Tests

```powershell
pytest
```
