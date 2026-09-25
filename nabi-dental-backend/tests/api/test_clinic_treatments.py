import io
import uuid

import pytest
from PIL import Image

from tests.api.conftest import auth_header, login


def _png_bytes() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (240, 240), color=(80, 80, 80)).save(buffer, format="PNG")
    return buffer.getvalue()


async def _treatment_id(client, headers, name: str) -> str:
    treatments = (await client.get("/api/v1/treatments", headers=headers, params={"page_size": 100})).json()["items"]
    return next(item["id"] for item in treatments if item["name"] == name)


@pytest.mark.asyncio
async def test_patient_rct_history_and_finance_total(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    rct_id = await _treatment_id(client, headers, "RCT")
    crown_id = await _treatment_id(client, headers, "Crown")

    patient = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "Ali Khan", "phone": "03001234567"},
    )
    assert patient.status_code == 201, patient.text
    patient_id = patient.json()["id"]

    first = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": rct_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-20",
            "amount": "8000.00",
            "sub_treatment": "RCT",
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
    assert body["details"]["tooth_number"] == "26"

    second = await client.post(
        "/api/v1/treatment-transactions",
        headers=headers,
        json={
            "treatment_id": crown_id,
            "patient_id": patient_id,
            "transaction_date": "2026-09-25",
            "amount": "15000.00",
            "sub_treatment": "Crown",
            "details": {"kind": "crown", "tooth_number": "26", "material": "Zirconia", "units": 1},
        },
    )
    assert second.status_code == 201, second.text
    assert second.json()["serial_no"] == 2

    history = await client.get(f"/api/v1/patients/{patient_id}/treatments", headers=headers)
    assert history.status_code == 200
    assert history.json()["total"] == 2
    assert {item["treatment_name"] for item in history.json()["items"]} == {"RCT", "Crown"}

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
    rct_id = await _treatment_id(client, headers, "RCT")
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
