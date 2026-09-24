import os
import subprocess
import sys

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.core.config import settings
from app.core.rate_limit import rate_limiter
from app.db.seed import seed_database
from app.db.session import SessionLocal, engine
from app.main import app


@pytest.fixture(scope="session", autouse=True)
def setup_database():
    env = os.environ.copy()
    env["DATABASE_URL"] = settings.DATABASE_URL
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        check=True,
        cwd=os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        env=env,
    )


@pytest.fixture(autouse=True)
async def reset_data():
    rate_limiter._hits.clear()
    async with engine.begin() as connection:
        await connection.execute(
            text(
                "TRUNCATE TABLE "
                "sync_changes, construction_purchases, construction_materials, construction_material_categories, "
                "home_budgets, home_expenses, home_expense_categories, "
                "clinic_expenses, clinic_expense_categories, treatment_transactions, "
                "treatments, treatment_categories, refresh_tokens, users, clinics "
                "RESTART IDENTITY CASCADE"
            )
        )
    async with SessionLocal() as session:
        await seed_database(session)
    yield


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as instance:
        yield instance


async def login(client: AsyncClient, email: str | None = None, password: str | None = None) -> dict:
    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": email or settings.OWNER_EMAIL,
            "password": password or settings.OWNER_PASSWORD,
            "device_id": "test-device",
            "device_name": "pytest",
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}
