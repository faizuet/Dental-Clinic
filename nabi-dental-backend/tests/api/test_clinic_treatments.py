import io
import uuid

import pytest
from PIL import Image

from tests.api.conftest import auth_header, login


def _png_bytes() -> bytes:
    from PIL import ImageDraw

    image = Image.new("L", (240, 240), color=18)
    ImageDraw.Draw(image).ellipse((36, 28, 204, 212), fill=170)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _landscape_bytes() -> bytes:
    image = Image.new("RGB", (240, 240), color=(70, 160, 240))
    for y in range(120, 240):
        for x in range(240):
            image.putpixel((x, y), (40, 150, 55))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _intraoral_bytes() -> bytes:
    image = Image.new("RGB", (240, 240), color=(180, 70, 80))
    for y in range(70, 170):
        for x in range(50, 190):
            image.putpixel((x, y), (245, 240, 230))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


async def _treatment_id(client, headers, name: str) -> str:
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100, "active": True})).json()["items"]
    return next(item["id"] for item in treatments if item["name"] == name)


@pytest.mark.asyncio
async def test_patient_rct_history_and_finance_total(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    rct_id = await _treatment_id(client, headers, "Root Canal Treatment (RCT)")
    crown_id = await _treatment_id(client, headers, "Zirconia Crown")

    patient = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "Ali Khan", "phone": "03001234567"},
    )
    assert patient.status_code == 201, patient.text
    assert patient.json()["phone"] == "03001234567"
    patient_id = patient.json()["id"]
    fetched = await client.get(f"/api/v1/patients/{patient_id}", headers=headers)
    assert fetched.status_code == 200
    assert fetched.json()["phone"] == "03001234567"
    listed = await client.get("/api/v1/patients", headers=headers, params={"search": "Ali"})
    assert listed.status_code == 200
    assert listed.json()["items"][0]["phone"] == "03001234567"

    first = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": rct_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-20",
            "amount": "8000.00",
            "sub_treatment": "Root Canal Treatment (RCT)",
            "details": {
                "kind": "rct",
                "tooth_number": "26",
                "tooth_name": "Upper Left First Molar",
                "canals": 3,
                "length_mm": "21",
            },
            "notes": "Working length confirmed",
        },
    )
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["serial_no"] == 1
    assert body["patient_name"] == "Ali Khan"
    assert body["patient_phone"] == "03001234567"
    assert body["details"]["tooth_number"] == "26"
    assert body["sub_treatment"] == "Root Canal Treatment (RCT)"

    second = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": crown_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-25",
            "amount": "15000.00",
            "sub_treatment": "Zirconia Crown",
            "details": {"kind": "crown", "tooth_number": "26", "material": "Zirconia", "units": 1},
        },
    )
    assert second.status_code == 201, second.text
    assert second.json()["serial_no"] == 2

    history = await client.get(f"/api/v1/patients/{patient_id}/treatments", headers=headers)
    assert history.status_code == 200
    assert history.json()["total"] == 2
    assert {item["treatment_name"] for item in history.json()["items"]} == {
        "Root Canal Treatment (RCT)",
        "Zirconia Crown",
    }

    dashboard = await client.get(
        "/api/v1/dashboard/clinic",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-20", "to_date": "2026-09-25"},
    )
    assert dashboard.json()["total_income"] == "23000.00"

    report = await client.get(
        "/api/v1/reports/clinic",
        headers=headers,
        params={"from_date": "2026-09-01", "to_date": "2026-09-30"},
    )
    assert report.status_code == 200
    assert report.json()["patient_count"] == 1
    assert report.json()["income_count"] == 2
    assert report.json()["income_lines"][0]["patient_name"] == "Ali Khan"


@pytest.mark.asyncio
async def test_xray_upload_and_treatment_pdf(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    rct_id = await _treatment_id(client, headers, "Root Canal Treatment (RCT)")
    created = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={"treatment_id": rct_id, "transaction_date": "2026-09-21", "amount": "8000.00"},
    )
    assert created.status_code == 201
    tx_id = created.json()["id"]

    empty = await client.post(
        f"/api/v1/treatment-transactions/{tx_id}/attachments",
        headers=headers,
        files={"file": ("empty.png", b"", "image/png")},
        data={"label": "before"},
    )
    assert empty.status_code in {400, 422}

    uploaded = await client.post(
        f"/api/v1/treatment-transactions/{tx_id}/attachments",
        headers=headers,
        files={"file": ("xray.png", _png_bytes(), "image/png")},
        data={"label": "before"},
    )
    assert uploaded.status_code == 201, uploaded.text
    attachment_id = uploaded.json()["id"]

    image = await client.get(
        f"/api/v1/treatment-transactions/{tx_id}/attachments/{attachment_id}/file",
        headers=headers,
    )
    assert image.status_code == 200
    assert image.headers["content-type"].startswith("image/")

    pdf = await client.get(f"/api/v1/treatment-transactions/{tx_id}/export", headers=headers)
    assert pdf.status_code == 200
    assert pdf.headers["content-type"].startswith("application/pdf")
    assert pdf.content[:4] == b"%PDF"

    other_tx = str(uuid.uuid4())
    leaked = await client.get(
        f"/api/v1/treatment-transactions/{other_tx}/attachments/{attachment_id}/file",
        headers=headers,
    )
    assert leaked.status_code == 404

    rejected = await client.post(
        f"/api/v1/treatment-transactions/{tx_id}/attachments",
        headers=headers,
        files={"file": ("park.png", _landscape_bytes(), "image/png")},
        data={"label": "before"},
    )
    assert rejected.status_code == 422, rejected.text
    assert "dental" in rejected.json()["error"]["message"].lower()

    intraoral = await client.post(
        f"/api/v1/treatment-transactions/{tx_id}/attachments",
        headers=headers,
        files={"file": ("mouth.png", _intraoral_bytes(), "image/png")},
        data={"label": "after"},
    )
    assert intraoral.status_code == 201, intraoral.text


@pytest.mark.asyncio
async def test_patch_treatment_updates_original_record(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    rct_id = await _treatment_id(client, headers, "Root Canal Treatment (RCT)")
    patient = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "Edit Patient", "phone": "03001112233"},
    )
    assert patient.status_code == 201, patient.text
    patient_id = patient.json()["id"]

    created = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": rct_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-20",
            "amount": "8000.00",
            "sub_treatment": "Root Canal Treatment (RCT)",
            "details": {
                "kind": "rct",
                "tooth_number": "26",
                "tooth_name": "Upper Left First Molar",
                "canals": 3,
                "length_mm": "21",
            },
            "notes": "Working length confirmed",
        },
    )
    assert created.status_code == 201, created.text
    tx_id = created.json()["id"]
    serial = created.json()["serial_no"]
    version = created.json()["version"]

    updated = await client.patch(
        f"/api/v1/treatment-transactions/{tx_id}",
        headers=headers,
        json={
            "version": version,
            "amount": "8500.00",
            "notes": "Length updated to 22 mm",
            "sub_treatment": "Root Canal Treatment (RCT)",
            "details": {
                "kind": "rct",
                "tooth_number": "16",
                "tooth_name": "Upper Right First Molar",
                "canals": 4,
                "length_mm": "22",
            },
        },
    )
    assert updated.status_code == 200, updated.text
    body = updated.json()
    assert body["id"] == tx_id
    assert body["serial_no"] == serial
    assert body["amount"] == "8500.00"
    assert body["notes"] == "Length updated to 22 mm"
    assert body["details"]["tooth_number"] == "16"
    assert body["details"]["canals"] == 4
    assert body["details"]["length_mm"] == "22"

    listed = await client.get(
        f"/api/v1/patients/{patient_id}/treatments",
        headers=headers,
    )
    assert listed.status_code == 200
    assert listed.json()["total"] == 1
    assert listed.json()["items"][0]["id"] == tx_id
    assert listed.json()["items"][0]["details"]["tooth_number"] == "16"


@pytest.mark.asyncio
async def test_multi_treatment_visit_is_one_record(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    rct_id = await _treatment_id(client, headers, "Root Canal Treatment (RCT)")
    extraction_id = await _treatment_id(client, headers, "Simple Extraction")
    filling_id = await _treatment_id(client, headers, "Permanent Filling")
    patient = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "Multi Visit", "phone": "03009998877"},
    )
    assert patient.status_code == 201, patient.text
    patient_id = patient.json()["id"]

    created = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": rct_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-22",
            "amount": "18000.00",
            "sub_treatment": "Root Canal Treatment (RCT), Simple Extraction, Permanent Filling",
            "details": {
                "kind": "visit",
                "items": [
                    {
                        "id": str(uuid.uuid4()),
                        "treatment_id": rct_id,
                        "treatment_name": "Root Canal Treatment (RCT)",
                        "sub_treatment": "Root Canal Treatment (RCT)",
                        "kind": "rct",
                        "tooth_number": "16",
                        "canals": 3,
                        "length_mm": "21",
                        "amount": "8000.00",
                    },
                    {
                        "id": str(uuid.uuid4()),
                        "treatment_id": extraction_id,
                        "treatment_name": "Simple Extraction",
                        "sub_treatment": "Simple Extraction",
                        "kind": "general",
                        "tooth_number": "18",
                        "amount": "5000.00",
                    },
                    {
                        "id": str(uuid.uuid4()),
                        "treatment_id": filling_id,
                        "treatment_name": "Permanent Filling",
                        "sub_treatment": "Permanent Filling",
                        "kind": "general",
                        "tooth_number": "24",
                        "amount": "5000.00",
                    },
                ],
            },
        },
    )
    assert created.status_code == 201, created.text
    tx_id = created.json()["id"]
    serial = created.json()["serial_no"]
    assert created.json()["amount"] == "18000.00"
    assert len(created.json()["details"]["items"]) == 3
    assert created.json()["details"]["items"][0]["tooth_number"] == "16"
    assert created.json()["details"]["items"][1]["tooth_number"] == "18"

    history = await client.get(f"/api/v1/patients/{patient_id}/treatments", headers=headers)
    assert history.status_code == 200
    assert history.json()["total"] == 1
    assert history.json()["items"][0]["id"] == tx_id

    extra = str(uuid.uuid4())
    updated = await client.patch(
        f"/api/v1/treatment-transactions/{tx_id}",
        headers=headers,
        json={
            "version": created.json()["version"],
            "amount": "20000.00",
            "sub_treatment": "Root Canal Treatment (RCT), Simple Extraction, Permanent Filling, Zirconia Crown",
            "details": {
                "kind": "visit",
                "items": [
                    *created.json()["details"]["items"],
                    {
                        "id": extra,
                        "treatment_id": await _treatment_id(client, headers, "Zirconia Crown"),
                        "treatment_name": "Zirconia Crown",
                        "sub_treatment": "Zirconia Crown",
                        "kind": "crown",
                        "tooth_number": "16",
                        "amount": "2000.00",
                    },
                ],
            },
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["id"] == tx_id
    assert updated.json()["serial_no"] == serial
    assert len(updated.json()["details"]["items"]) == 4

    trimmed = await client.patch(
        f"/api/v1/treatment-transactions/{tx_id}",
        headers=headers,
        json={
            "version": updated.json()["version"],
            "amount": "15000.00",
            "details": {
                "kind": "visit",
                "items": [item for item in updated.json()["details"]["items"] if item["id"] != extra],
            },
        },
    )
    assert trimmed.status_code == 200, trimmed.text
    assert trimmed.json()["id"] == tx_id
    assert len(trimmed.json()["details"]["items"]) == 3
    history_after = await client.get(f"/api/v1/patients/{patient_id}/treatments", headers=headers)
    assert history_after.json()["total"] == 1
    assert history_after.json()["items"][0]["id"] == tx_id
    assert [item["tooth_number"] for item in history_after.json()["items"][0]["details"]["items"]] == ["16", "18", "24"]

    pdf = await client.get(f"/api/v1/treatment-transactions/{tx_id}/export", headers=headers)
    assert pdf.status_code == 200, pdf.text
    assert pdf.headers["content-type"].startswith("application/pdf")
    assert pdf.content[:4] == b"%PDF"


@pytest.mark.asyncio
async def test_patient_phone_must_be_pakistani_mobile(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    for phone in ["0300123456", "030012345678", "923001234567", "0300ABC4567", "0300 1234567"]:
        created = await client.post("/api/v1/patients", headers=headers, json={"name": "Phone Check", "phone": phone})
        assert created.status_code == 422, created.text
    created = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "Phone Check", "phone": "03123456789"},
    )
    assert created.status_code == 201, created.text
    patched = await client.patch(
        f"/api/v1/patients/{created.json()['id']}",
        headers=headers,
        json={"version": created.json()["version"], "phone": "0300123456"},
    )
    assert patched.status_code == 422, patched.text


@pytest.mark.asyncio
async def test_deleting_patient_keeps_treatment_payments(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    rct_id = await _treatment_id(client, headers, "Root Canal Treatment (RCT)")
    patient = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "Paid Patient", "phone": "03001234567"},
    )
    assert patient.status_code == 201, patient.text
    patient_id = patient.json()["id"]
    visit = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": rct_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-20",
            "amount": "8000.00",
            "sub_treatment": "Root Canal Treatment (RCT)",
        },
    )
    assert visit.status_code == 201, visit.text
    tx_id = visit.json()["id"]

    deleted = await client.delete(
        f"/api/v1/patients/{patient_id}",
        headers=headers,
        params={"version": patient.json()["version"]},
    )
    assert deleted.status_code == 204, deleted.text
    missing = await client.get(f"/api/v1/patients/{patient_id}", headers=headers)
    assert missing.status_code == 404

    kept = await client.get(f"/api/v1/treatment-transactions/{tx_id}", headers=headers)
    assert kept.status_code == 200, kept.text
    assert kept.json()["id"] == tx_id
    assert kept.json()["amount"] == "8000.00"
    assert kept.json()["patient_id"] == patient_id
    assert kept.json()["patient_name"] == "Paid Patient"
    assert kept.json()["patient_phone"] == "03001234567"

    dashboard = await client.get(
        "/api/v1/dashboard/clinic",
        headers=headers,
        params={"period": "custom", "from_date": "2026-09-20", "to_date": "2026-09-20"},
    )
    assert dashboard.status_code == 200
    assert dashboard.json()["total_income"] == "8000.00"
