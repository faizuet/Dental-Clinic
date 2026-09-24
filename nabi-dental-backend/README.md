# Nabi Dental Clinic Backend

FastAPI backend for the Nabi Dental Clinic finance management application.

## Stack

- Python 3.12
- FastAPI
- SQLAlchemy 2.x async + asyncpg
- PostgreSQL 16
- Alembic
- Pydantic v2
- Docker
- Pytest

## Local start

1. Copy `.env.example` to `.env` and set `JWT_SECRET_KEY`.
2. Run `docker compose up --build`.
   - Postgres is published on host port **5433** to avoid colliding with other local databases.
   - The app container still talks to Postgres as `db:5432`.
3. The container runs migrations and seeds the owner account on startup.
4. Open `http://localhost:8001/docs`.
5. Health: `GET /health`. Readiness: `GET /ready`.

Default seed login (development only):

- Email: `owner@example.com`
- Password: `ChangeMeNow!1`

## Tests

PostgreSQL must be reachable at `localhost:5433` (or `TEST_DATABASE_URL`).

```bash
pip install -r requirements.txt
pytest
```

## Seed

```bash
python -m app.db.seed
```
