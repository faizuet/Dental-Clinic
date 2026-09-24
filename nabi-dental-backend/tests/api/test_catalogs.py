import uuid

import pytest

from tests.api.conftest import auth_header, login


@pytest.mark.asyncio
async def test_seeded_catalogs_and_duplicate_names(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatments = await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})
    assert treatments.status_code == 200
    assert treatments.json()["total"] == 23
    categories = await client.get("/api/v1/treatment-categories", headers=headers, params={"page_size": 50})
    assert categories.json()["total"] == 11
    clinic_cats = await client.get("/api/v1/clinic-expense-categories", headers=headers)
    assert clinic_cats.json()["total"] == 7
    home_cats = await client.get("/api/v1/home-expense-categories", headers=headers)
    assert home_cats.json()["total"] == 9

    duplicate = await client.post("/api/v1/treatments", headers=headers, json={
        "category_id": treatments.json()["items"][0]["category_id"],
        "name": "rct",
    })
    assert duplicate.status_code == 409


@pytest.mark.asyncio
async def test_deactivate_instead_of_deleting_used_treatment(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    treatment = next(item for item in treatments if item["name"] == "RCT")
    created = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": treatment["id"],
            "transaction_date": "2026-09-17",
            "amount": "5000.00",
        },
    )
    assert created.status_code == 201
    deleted = await client.delete(
        f"/api/v1/treatments/{treatment['id']}",
        headers=headers,
        params={"version": treatment["version"]},
    )
    assert deleted.status_code == 409
    updated = await client.patch(
        f"/api/v1/treatments/{treatment['id']}",
        headers=headers,
        json={"version": treatment["version"], "is_active": False},
    )
    assert updated.status_code == 200
    assert updated.json()["is_active"] is False
