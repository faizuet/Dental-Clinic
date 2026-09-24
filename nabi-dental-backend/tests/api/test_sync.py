import uuid

import pytest

from tests.api.conftest import auth_header, login


@pytest.mark.asyncio
async def test_sync_push_idempotent_and_conflict(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    treatment_id = next(item["id"] for item in treatments if item["name"] == "RCT")
    entity_id = str(uuid.uuid4())
    change_id = str(uuid.uuid4())
    payload = {
        "device_id": "device-1",
        "changes": [
            {
                "client_change_id": change_id,
                "entity": "treatment_transaction",
                "operation": "create",
                "entity_id": entity_id,
                "data": {
                    "treatment_id": treatment_id,
                    "transaction_date": "2026-09-17",
                    "amount": "5000.00",
                    "quantity": 1,
                },
            }
        ],
    }
    first = await client.post("/api/v1/sync/push", headers=headers, json=payload)
    assert first.status_code == 200
    assert first.json()["results"][0]["status"] == "applied"
    replay = await client.post("/api/v1/sync/push", headers=headers, json=payload)
    assert replay.status_code == 200
    assert replay.json()["results"][0]["status"] == "applied"
    assert replay.json()["results"][0]["record"]["id"] == entity_id

    update = await client.post(
        "/api/v1/sync/push",
        headers=headers,
        json={
            "device_id": "device-1",
            "changes": [
                {
                    "client_change_id": str(uuid.uuid4()),
                    "entity": "treatment_transaction",
                    "operation": "update",
                    "entity_id": entity_id,
                    "base_version": 1,
                    "data": {"amount": "5500.00"},
                }
            ],
        },
    )
    assert update.json()["results"][0]["status"] == "applied"
    conflict = await client.post(
        "/api/v1/sync/push",
        headers=headers,
        json={
            "device_id": "device-2",
            "changes": [
                {
                    "client_change_id": str(uuid.uuid4()),
                    "entity": "treatment_transaction",
                    "operation": "update",
                    "entity_id": entity_id,
                    "base_version": 1,
                    "data": {"amount": "6000.00"},
                }
            ],
        },
    )
    assert conflict.json()["results"][0]["status"] == "conflict"
    assert conflict.json()["results"][0]["record"]["version"] == 2

    bootstrap = await client.post("/api/v1/sync/bootstrap", headers=headers)
    assert bootstrap.status_code == 200
    assert bootstrap.json()["cursor"]
    pull = await client.get("/api/v1/sync/pull", headers=headers, params={"cursor": bootstrap.json()["cursor"]})
    assert pull.status_code == 200
