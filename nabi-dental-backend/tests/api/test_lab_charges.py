import uuid

import pytest

from tests.api.conftest import auth_header, login

DAY = {"period": "custom", "from_date": "2026-09-10", "to_date": "2026-09-10"}


async def _headers(client) -> dict[str, str]:
    return auth_header(await login(client))


async def _treatment_id(client, headers, name: str = "Zirconia Crown") -> str:
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    return next(item["id"] for item in treatments if item["name"] == name)


async def _category_id(client, headers, name: str = "Materials") -> str:
    categories = (await client.get("/api/v1/clinic-expense-categories", headers=headers)).json()["items"]
    return next(item["id"] for item in categories if item["name"] == name)


async def _patient(client, headers, name: str, phone: str) -> str:
    response = await client.post("/api/v1/patients", headers=headers, json={"name": name, "phone": phone})
    assert response.status_code == 201, response.text
    return response.json()["id"]


async def _visit(client, headers, patient_id: str | None, amount: str = "10000.00", day: str = "2026-09-10") -> str:
    response = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": await _treatment_id(client, headers),
            "patient_id": patient_id,
            "transaction_date": day,
            "amount": amount,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


async def _lab_charge(client, headers, **body) -> dict:
    response = await client.post(
        "/api/v1/lab-charges",
        headers=headers,
        json={"charge_date": "2026-09-10", "amount": "1500.00", **body},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _dashboard(client, headers) -> dict:
    response = await client.get("/api/v1/dashboard/clinic", headers=headers, params=DAY)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.asyncio
async def test_lab_charge_crud_links_patient_and_visit(client):
    headers = await _headers(client)
    ali = await _patient(client, headers, "Ali Khan", "03001234567")
    sara = await _patient(client, headers, "Sara Malik", "03007654321")
    visit = await _visit(client, headers, ali)

    created = await _lab_charge(client, headers, transaction_id=visit, lab_name="Smile Ceramics", notes="Crown 26")
    assert created["patient_id"] == ali
    assert created["transaction_id"] == visit
    assert created["lab_name"] == "Smile Ceramics"
    assert created["amount"] == "1500.00"

    listed = await client.get("/api/v1/lab-charges", headers=headers, params={"patient_id": ali})
    assert listed.json()["total"] == 1
    searched = await client.get("/api/v1/lab-charges", headers=headers, params={"search": "Ali"})
    assert [item["id"] for item in searched.json()["items"]] == [created["id"]]

    updated = await client.patch(
        f"/api/v1/lab-charges/{created['id']}",
        headers=headers,
        json={"version": created["version"], "amount": "1800.00", "lab_name": "  Pearl Dental Lab  "},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["amount"] == "1800.00"
    assert updated.json()["lab_name"] == "Pearl Dental Lab"
    assert updated.json()["version"] == created["version"] + 1

    mismatch = await client.post(
        "/api/v1/lab-charges",
        headers=headers,
        json={"charge_date": "2026-09-10", "amount": "500.00", "patient_id": sara, "transaction_id": visit},
    )
    assert mismatch.status_code == 400
    assert mismatch.json()["error"]["code"] == "VALIDATION_ERROR"

    unknown = await client.post(
        "/api/v1/lab-charges",
        headers=headers,
        json={"charge_date": "2026-09-10", "amount": "500.00", "patient_id": str(uuid.uuid4())},
    )
    assert unknown.status_code == 400

    unlinked = await _lab_charge(client, headers, amount="300.00")
    assert unlinked["patient_id"] is None
    assert unlinked["transaction_id"] is None

    deleted = await client.delete(
        f"/api/v1/lab-charges/{created['id']}",
        headers=headers,
        params={"version": updated.json()["version"]},
    )
    assert deleted.status_code == 204
    assert (await client.get(f"/api/v1/lab-charges/{created['id']}", headers=headers)).status_code == 404


@pytest.mark.asyncio
async def test_dashboard_keeps_lab_charges_out_of_clinic_expenses(client):
    headers = await _headers(client)
    await _visit(client, headers, None)
    expense = await client.post(
        "/api/v1/clinic-expenses",
        headers=headers,
        json={"category_id": await _category_id(client, headers), "expense_date": "2026-09-10", "amount": "2000.00"},
    )
    assert expense.status_code == 201
    charge = await _lab_charge(client, headers)
    await _lab_charge(client, headers, charge_date="2026-09-11", amount="999.00")

    body = await _dashboard(client, headers)
    assert body["total_income"] == "10000.00"
    assert body["total_expenses"] == "2000.00"
    assert body["total_lab_charges"] == "1500.00"
    assert body["profit"] == "6500.00"

    edited = await client.patch(
        f"/api/v1/lab-charges/{charge['id']}",
        headers=headers,
        json={"version": charge["version"], "amount": "2500.00"},
    )
    body = await _dashboard(client, headers)
    assert body["total_expenses"] == "2000.00"
    assert body["total_lab_charges"] == "2500.00"
    assert body["profit"] == "5500.00"

    await client.delete(
        f"/api/v1/lab-charges/{charge['id']}",
        headers=headers,
        params={"version": edited.json()["version"]},
    )
    body = await _dashboard(client, headers)
    assert body["total_lab_charges"] == "0.00"
    assert body["total_expenses"] == "2000.00"
    assert body["profit"] == "8000.00"


@pytest.mark.asyncio
async def test_clinic_report_lists_lab_charges_separately(client):
    headers = await _headers(client)
    ali = await _patient(client, headers, "Ali Khan", "03001234567")
    visit = await _visit(client, headers, ali)
    await client.post(
        "/api/v1/clinic-expenses",
        headers=headers,
        json={"category_id": await _category_id(client, headers), "expense_date": "2026-09-10", "amount": "2000.00"},
    )
    await _lab_charge(client, headers, transaction_id=visit, lab_name="Smile Ceramics")
    params = {"from_date": "2026-09-01", "to_date": "2026-09-30", "group_by": "day"}

    report = await client.get("/api/v1/reports/clinic", headers=headers, params=params)
    assert report.status_code == 200, report.text
    body = report.json()
    assert body["total_expenses"] == "2000.00"
    assert body["total_lab_charges"] == "1500.00"
    assert body["profit"] == "6500.00"
    assert body["expense_count"] == 1
    assert body["lab_charge_count"] == 1
    assert [item["name"] for item in body["expenses_by_category"]] == ["Materials"]
    line = body["lab_charge_lines"][0]
    assert line["name"] == "Smile Ceramics"
    assert line["patient_name"] == "Ali Khan"
    assert line["sub_treatment"] == "Zirconia Crown"
    point = body["timeline"][0]
    assert point["expenses"] == "2000.00"
    assert point["lab_charges"] == "1500.00"
    assert point["profit"] == "6500.00"

    for fmt in ("pdf", "xlsx"):
        export = await client.get(
            "/api/v1/reports/clinic/export",
            headers=headers,
            params={"from_date": "2026-09-01", "to_date": "2026-09-30", "format": fmt},
        )
        assert export.status_code == 200, export.text


@pytest.mark.asyncio
async def test_lab_charge_sync_push_and_bootstrap(client):
    headers = await _headers(client)
    entity_id = str(uuid.uuid4())
    pushed = await client.post(
        "/api/v1/sync/push",
        headers=headers,
        json={
            "device_id": "device-1",
            "changes": [
                {
                    "client_change_id": str(uuid.uuid4()),
                    "entity": "lab_charge",
                    "operation": "create",
                    "entity_id": entity_id,
                    "data": {"charge_date": "2026-09-10", "amount": "1200.00", "lab_name": "Smile Ceramics"},
                }
            ],
        },
    )
    result = pushed.json()["results"][0]
    assert result["status"] == "applied", result
    assert result["record"]["id"] == entity_id

    bootstrap = await client.post("/api/v1/sync/bootstrap", headers=headers)
    assert [item["id"] for item in bootstrap.json()["data"]["lab_charges"]] == [entity_id]
    assert (await _dashboard(client, headers))["total_lab_charges"] == "1200.00"


@pytest.mark.asyncio
async def test_lab_charges_are_not_a_clinic_expense_category(client):
    headers = await _headers(client)
    categories = (await client.get("/api/v1/clinic-expense-categories", headers=headers)).json()["items"]
    assert "lab charges" not in {item["name"].lower() for item in categories}
    for name in ("Lab Charges", " lab "):
        response = await client.post("/api/v1/clinic-expense-categories", headers=headers, json={"name": name})
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "VALIDATION_ERROR"
