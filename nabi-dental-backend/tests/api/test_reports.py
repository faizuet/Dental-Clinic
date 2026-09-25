import pytest

from tests.api.conftest import auth_header, login


@pytest.mark.asyncio
async def test_clinic_report_and_exports(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    treatment_id = next(item["id"] for item in treatments if item["name"] == "RCT")
    await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={"treatment_id": treatment_id, "transaction_date": "2026-09-17", "amount": "5000.00"},
    )
    report = await client.get(
        "/api/v1/reports/clinic",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30", "group_by": "day"},
    )
    assert report.status_code == 200
    body = report.json()
    assert body["total_income"] == "5000.00"
    assert body["income_by_treatment"][0]["name"] == "RCT"
    pdf = await client.get(
        "/api/v1/reports/clinic/export",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30", "format": "pdf"},
    )
    assert pdf.status_code == 200
    assert pdf.headers["content-type"].startswith("application/pdf")
    assert "attachment" in pdf.headers["content-disposition"]
    xlsx = await client.get(
        "/api/v1/reports/clinic/export",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30", "format": "xlsx"},
    )
    assert xlsx.status_code == 200
    assert "spreadsheetml" in xlsx.headers["content-type"]


@pytest.mark.asyncio
async def test_clinic_report_includes_all_dates_in_range(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    rct_id = next(item["id"] for item in treatments if item["name"] == "RCT")
    crown_id = next(item["id"] for item in treatments if item["name"] == "Crown")
    scaling_id = next(item["id"] for item in treatments if item["name"] == "Scaling")
    for date_value, treatment_id, amount in [
        ("2026-09-01", rct_id, "8000.00"),
        ("2026-09-15", crown_id, "15000.00"),
        ("2026-09-30", scaling_id, "5000.00"),
    ]:
        created = await client.post(
            "/api/v1/treatment-transactions",
            headers=headers,
            json={"treatment_id": treatment_id, "transaction_date": date_value, "amount": amount},
        )
        assert created.status_code == 201, created.text

    report = await client.get(
        "/api/v1/reports/clinic",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30"},
    )
    assert report.status_code == 200
    body = report.json()
    assert body["income_count"] == 3
    assert body["total_income"] == "28000.00"
    dates = {item["entry_date"] for item in body["income_lines"]}
    assert dates == {"2026-09-01", "2026-09-15", "2026-09-30"}

    empty = await client.get(
        "/api/v1/reports/clinic",
        headers=headers,
        params={"from_date": "2026-08-01", "to_date": "2026-08-31"},
    )
    assert empty.json()["income_count"] == 0
    assert empty.json()["total_income"] == "0.00"
    pdf = await client.get(
        "/api/v1/reports/clinic/export",
        headers=headers,
        params={"from_date": "2026-08-01", "to_date": "2026-08-31", "format": "pdf"},
    )
    assert pdf.status_code == 200
    assert pdf.content[:4] == b"%PDF"


@pytest.mark.asyncio
async def test_construction_report_and_exports(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    categories = (await client.get("/api/v1/construction-material-categories", headers=headers)).json()["items"]
    structure_id = next(item["id"] for item in categories if item["name"] == "Structure")
    materials = (
        await client.get(
            "/api/v1/construction-materials",
            headers=headers,
            params={"category_id": structure_id, "page_size": 100},
        )
    ).json()["items"]
    cement = next(item for item in materials if item["name"] == "Cement")
    created = await client.post(
        "/api/v1/construction-purchases",
        headers=headers,
        json={
            "material_id": cement["id"],
            "purchase_date": "2026-09-24",
            "quantity": "10",
            "unit_price": "1450.00",
            "supplier": "Local kiln",
        },
    )
    assert created.status_code == 201, created.text
    report = await client.get(
        "/api/v1/reports/construction",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30", "group_by": "month"},
    )
    assert report.status_code == 200, report.text
    body = report.json()
    assert body["total_expenses"] == "14500.00"
    assert body["purchase_count"] == 1
    assert body["expenses_by_category"][0]["name"] == "Structure"
    assert body["purchases"][0]["material_name"] == "Cement"
    pdf = await client.get(
        "/api/v1/reports/construction/export",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30", "format": "pdf"},
    )
    assert pdf.status_code == 200
    assert pdf.headers["content-type"].startswith("application/pdf")
    xlsx = await client.get(
        "/api/v1/reports/construction/export",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30", "format": "xlsx"},
    )
    assert xlsx.status_code == 200
    assert "spreadsheetml" in xlsx.headers["content-type"]


@pytest.mark.asyncio
async def test_settings_update(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    updated = await client.patch(
        "/api/v1/settings",
        headers=headers,
        json={"clinic_name": "Nabi Dental", "default_home_budget": "25000.00"},
    )
    assert updated.status_code == 200
    assert updated.json()["clinic_name"] == "Nabi Dental"
    assert updated.json()["default_home_budget"] == "25000.00"
