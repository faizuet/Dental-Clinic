import uuid
from datetime import date

import pytest

from tests.api.conftest import auth_header, login


async def _rct_id(client, headers) -> str:
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    return next(item["id"] for item in treatments if item["name"] == "RCT")


async def _lab_id(client, headers) -> str:
    categories = (await client.get("/api/v1/clinic-expense-categories", headers=headers)).json()["items"]
    return next(item["id"] for item in categories if item["name"] == "Lab Charges")


@pytest.mark.asyncio
async def test_batch_transactions_and_clinic_dashboard(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatment_id = await _rct_id(client, headers)
    category_id = await _lab_id(client, headers)
    first_id = str(uuid.uuid4())
    second_id = str(uuid.uuid4())
    batch = await client.post(
        "/api/v1/treatment-transactions/batch",
        headers=headers,
        json={
            "items": [
                {
                    "id": first_id,
                    "treatment_id": treatment_id,
                    "transaction_date": "2026-09-17",
                    "amount": "5000.00",
                    "quantity": 1,
                },
                {
                    "id": second_id,
                    "treatment_id": treatment_id,
                    "transaction_date": "2026-09-17",
                    "amount": "1500.00",
                },
            ]
        },
    )
    assert batch.status_code == 201
    expense = await client.post(
        "/api/v1/clinic-expenses",
        headers=headers,
        json={"category_id": category_id, "expense_date": "2026-09-17", "amount": "2000.00"},
    )
    assert expense.status_code == 201
    dashboard = await client.get(
        "/api/v1/dashboard/clinic",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-17", "to_date": "2026-09-17"},
    )
    assert dashboard.status_code == 200
    body = dashboard.json()
    assert body["total_income"] == "6500.00"
    assert body["total_expenses"] == "2000.00"
    assert body["profit"] == "4500.00"


@pytest.mark.asyncio
async def test_negative_profit_and_soft_delete(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatment_id = await _rct_id(client, headers)
    category_id = await _lab_id(client, headers)
    await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={"treatment_id": treatment_id, "transaction_date": "2026-09-01", "amount": "1000.00"},
    )
    expense = (
        await client.post(
            "/api/v1/clinic-expenses",
            headers=headers,
            json={"category_id": category_id, "expense_date": "2026-09-01", "amount": "2500.00"},
        )
    ).json()
    dashboard = await client.get(
        "/api/v1/dashboard/clinic",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-01", "to_date": "2026-09-01"},
    )
    assert dashboard.json()["profit"] == "-1500.00"
    deleted = await client.delete(
        f"/api/v1/clinic-expenses/{expense['id']}",
        headers=headers,
        params={"version": expense["version"]},
    )
    assert deleted.status_code == 204
    after = await client.get(
        "/api/v1/dashboard/clinic",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-01", "to_date": "2026-09-01"},
    )
    assert after.json()["total_expenses"] == "0.00"
    assert after.json()["profit"] == "1000.00"


@pytest.mark.asyncio
async def test_version_conflict(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatment_id = await _rct_id(client, headers)
    created = (
        await client.post(
            "/api/v1/treatment-transactions",
            headers=headers,
            json={"treatment_id": treatment_id, "transaction_date": "2026-09-17", "amount": "5000.00"},
        )
    ).json()
    first = await client.patch(
        f"/api/v1/treatment-transactions/{created['id']}",
        headers=headers,
        json={"version": created["version"], "amount": "5500.00"},
    )
    assert first.status_code == 200
    conflict = await client.patch(
        f"/api/v1/treatment-transactions/{created['id']}",
        headers=headers,
        json={"version": created["version"], "amount": "6000.00"},
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "VERSION_CONFLICT"
