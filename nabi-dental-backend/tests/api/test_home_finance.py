import pytest

from tests.api.conftest import auth_header, login


@pytest.mark.asyncio
async def test_home_expenses_isolated_from_clinic(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    categories = (await client.get("/api/v1/home-expense-categories", headers=headers)).json()["items"]
    groceries = next(item["id"] for item in categories if item["name"] == "Groceries")
    created = await client.post(
        "/api/v1/home-expenses",
        headers=headers,
        json={"category_id": groceries, "expense_date": "2026-09-17", "amount": "4000.00"},
    )
    assert created.status_code == 201
    clinic = await client.get(
        "/api/v1/dashboard/clinic",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-17", "to_date": "2026-09-17"},
    )
    assert clinic.json()["total_income"] == "0.00"
    assert clinic.json()["total_expenses"] == "0.00"
    home = await client.get(
        "/api/v1/dashboard/home",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-17", "to_date": "2026-09-17"},
    )
    body = home.json()
    assert body["total_expenses"] == "4000.00"
    assert body["budget"] == "30000.00"
    assert body["remaining"] == "26000.00"
    assert body["percentage_used"] == "13.33"
    assert body["budget_source"] == "default"


@pytest.mark.asyncio
async def test_budget_override_and_overspend(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    created = await client.post(
        "/api/v1/home-budgets",
        headers=headers,
        json={"year": 2026, "month": 9, "amount": "1000.00"},
    )
    assert created.status_code == 201
    duplicate = await client.post(
        "/api/v1/home-budgets",
        headers=headers,
        json={"year": 2026, "month": 9, "amount": "2000.00"},
    )
    assert duplicate.status_code == 409
    categories = (await client.get("/api/v1/home-expense-categories", headers=headers)).json()["items"]
    groceries = next(item["id"] for item in categories if item["name"] == "Groceries")
    await client.post(
        "/api/v1/home-expenses",
        headers=headers,
        json={"category_id": groceries, "expense_date": "2026-09-10", "amount": "1500.00"},
    )
    home = await client.get(
        "/api/v1/dashboard/home",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-01", "to_date": "2026-09-30"},
    )
    body = home.json()
    assert body["budget"] == "1000.00"
    assert body["remaining"] == "-500.00"
    assert body["budget_source"] == "override"
    current = await client.get("/api/v1/home-budgets/current", headers=headers, params={"year": 2026, "month": 9})
    assert current.json()["source"] == "override"
    current_default = await client.get(
        "/api/v1/home-budgets/current", headers=headers, params={"year": 2026, "month": 8}
    )
    assert current_default.json()["source"] == "default"
    assert current_default.json()["amount"] == "30000.00"


@pytest.mark.asyncio
async def test_budget_upsert_updates_existing_month(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    created = await client.put(
        "/api/v1/home-budgets/current",
        headers=headers,
        json={"year": 2026, "month": 4, "amount": "12000.00"},
    )
    assert created.status_code == 200
    updated = await client.put(
        "/api/v1/home-budgets/current",
        headers=headers,
        json={"year": 2026, "month": 4, "amount": "18000.00", "id": "00000000-0000-0000-0000-000000000099"},
    )
    assert updated.status_code == 200
    assert updated.json()["amount"] == "18000.00"
    assert updated.json()["id"] == created.json()["id"]
    current = await client.get("/api/v1/home-budgets/current", headers=headers, params={"year": 2026, "month": 4})
    assert current.json()["amount"] == "18000.00"
    assert current.json()["source"] == "override"
