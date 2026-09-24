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
