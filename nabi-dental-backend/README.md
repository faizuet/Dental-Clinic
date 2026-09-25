# Nabi Dental Clinic API

FastAPI + PostgreSQL service for the clinic, home, and construction modules.

Full project documentation (features, data model, environment, and how to run the Flutter app) is in the [repository README](../README.md).

## Quick start

```powershell
copy .env.example .env
docker compose up --build
```

- API: `http://127.0.0.1:8001`
- Docs: `http://127.0.0.1:8001/docs`

Without Docker: create a venv, `pip install -r requirements.txt`, set `DATABASE_URL`, then `alembic upgrade head`, `python -m app.db.seed`, and `uvicorn app.main:app --reload --port 8000`.

## Tests

```powershell
pytest
```
