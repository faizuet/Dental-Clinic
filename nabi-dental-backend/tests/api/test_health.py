import pytest

from app.db.seed import seed_database
from app.db.session import SessionLocal


@pytest.mark.asyncio
async def test_health(client):
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    assert "X-Request-ID" in response.headers


@pytest.mark.asyncio
async def test_ready(client):
    response = await client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


@pytest.mark.asyncio
async def test_seed_is_idempotent():
    async with SessionLocal() as session:
        await seed_database(session)
        await seed_database(session)
