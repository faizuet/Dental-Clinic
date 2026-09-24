import pytest

from tests.api.conftest import auth_header, login


@pytest.mark.asyncio
async def test_construction_purchase_computes_total(client):
    tokens = await login(client)
    headers = auth_header(tokens)

    categories = await client.get("/api/v1/construction-material-categories", headers=headers)
    assert categories.status_code == 200, categories.text
    items = categories.json()["items"]
    assert any(item["name"] == "Structure" for item in items)
    structure_id = next(item["id"] for item in items if item["name"] == "Structure")

    materials = await client.get(
        "/api/v1/construction-materials",
        headers=headers,
        params={"category_id": structure_id, "page_size": 100},
    )
    assert materials.status_code == 200, materials.text
    cement = next(item for item in materials.json()["items"] if item["name"] == "Cement")

    created = await client.post(
        "/api/v1/construction-purchases",
        headers=headers,
        json={
            "material_id": cement["id"],
            "purchase_date": "2026-09-24",
            "quantity": "10",
            "unit_price": "1450.00",
            "supplier": "Local kiln",
            "notes": "First load",
        },
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["amount"] == "14500.00"
    assert body["unit"] == "bag"
    assert body["supplier"] == "Local kiln"

    listed = await client.get("/api/v1/construction-purchases", headers=headers)
    assert listed.status_code == 200
    assert listed.json()["total"] == 1
