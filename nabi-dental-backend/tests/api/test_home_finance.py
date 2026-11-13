import pytest

from app.core.constants import SEED_HOME_EXPENSE_CATEGORIES
from app.db.seed import seed_database
from app.db.session import SessionLocal
from tests.api.conftest import auth_header, login


async def _home_categories(client, headers):
    return (
        await client.get(
            "/api/v1/home-expense-categories",
            headers=headers,
            params={"page_size": 100, "active": True, "sort": "display_order"},
        )
    ).json()["items"]


@pytest.mark.asyncio
async def test_home_grocery_categories_replace_the_old_list(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    items = await _home_categories(client, headers)
    names = [item["name"] for item in items]
    assert names == SEED_HOME_EXPENSE_CATEGORIES
    assert "Groceries" not in names
    assert "Utilities" not in names


@pytest.mark.asyncio
async def test_home_expenses_isolated_from_clinic(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    categories = await _home_categories(client, headers)
    groceries = next(item["id"] for item in categories if item["name"] == "Milk / Yogurt")
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
    report = await client.get(
        "/api/v1/reports/home",
        headers=headers,
        params={"from_date": "2026-09-17", "to_date": "2026-09-17"},
    )
    assert report.status_code == 200
    assert report.json()["expenses_by_category"][0]["name"] == "Milk / Yogurt"
    assert report.json()["total_expenses"] == "4000.00"


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
    categories = await _home_categories(client, headers)
    groceries = next(item["id"] for item in categories if item["name"] == "Milk / Yogurt")
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


@pytest.mark.asyncio
async def test_used_old_home_category_stays_for_history(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    created = await client.post(
        "/api/v1/home-expense-categories",
        headers=headers,
        json={"name": "Groceries"},
    )
    assert created.status_code == 201
    category_id = created.json()["id"]
    unused = await client.post(
        "/api/v1/home-expense-categories",
        headers=headers,
        json={"name": "Old Household"},
    )
    assert unused.status_code == 201
    expense = await client.post(
        "/api/v1/home-expenses",
        headers=headers,
        json={"category_id": category_id, "expense_date": "2026-09-12", "amount": "750.00"},
    )
    assert expense.status_code == 201

    async with SessionLocal() as session:
        await seed_database(session)

    active = await _home_categories(client, headers)
    names = [item["name"] for item in active]
    assert names == SEED_HOME_EXPENSE_CATEGORIES
    assert "Groceries" not in names
    assert "Old Household" not in names

    inactive = (
        await client.get(
            "/api/v1/home-expense-categories",
            headers=headers,
            params={"page_size": 100, "active": False},
        )
    ).json()["items"]
    groceries = next(item for item in inactive if item["name"] == "Groceries")
    assert groceries["is_active"] is False
    assert groceries["id"] == category_id

    listed = await client.get(
        "/api/v1/home-expenses",
        headers=headers,
        params={"page_size": 100},
    )
    assert listed.json()["items"][0]["amount"] == "750.00"
    assert listed.json()["items"][0]["category_id"] == category_id

    report = await client.get(
        "/api/v1/reports/home",
        headers=headers,
        params={"from_date": "2026-09-12", "to_date": "2026-09-12"},
    )
    assert report.json()["expenses_by_category"][0]["name"] == "Groceries"
    assert report.json()["total_expenses"] == "750.00"

    missing = await client.get(f"/api/v1/home-expense-categories/{unused.json()['id']}", headers=headers)
    assert missing.status_code == 404
