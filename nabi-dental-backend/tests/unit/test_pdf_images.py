import base64
import re
import zlib
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path
from uuid import uuid4

from PIL import Image as PILImage

from app.exports.pdf import (
    PRIMARY,
    PRIMARY_DARK,
    _fit_image,
    _item_dental_rows,
    _treatment_images,
    render_clinic_pdf,
    render_treatment_pdf,
)
from app.schemas.report import ClinicReport, NamedAmount, PeriodWindow, ReportLine
from app.schemas.treatment_transaction import TreatmentTransactionRead


def _pdf_text(data: bytes) -> str:
    chunks = []
    for match in re.finditer(rb"stream\r?\n(.+?)endstream", data, re.S):
        raw = match.group(1).strip()
        if raw.endswith(b"~>"):
            try:
                raw = base64.a85decode(raw[:-2])
            except Exception:
                pass
        try:
            raw = zlib.decompress(raw)
        except Exception:
            pass
        chunks.append(raw.decode("latin-1", errors="ignore"))
    return "\n".join(chunks)


def test_fit_image_stays_inside_the_frame():
    width, height = _fit_image(4000, 2250, 190, 128)
    assert width <= 190.01
    assert height <= 128.01
    assert abs((width / height) - (4000 / 2250)) < 0.01


def test_treatment_images_use_framed_blocks(tmp_path: Path):
    photo = tmp_path / "before.png"
    PILImage.new("RGB", (1600, 900), color=(40, 80, 120)).save(photo, format="PNG")
    blocks = _treatment_images([("before", str(photo))])
    assert blocks
    assert blocks[0].text == "X-ray images"
    grid = blocks[1]
    frame = grid._cellvalues[0][0]
    image = frame._cellvalues[1][0]
    assert image.drawWidth <= 190.01
    assert image.drawHeight <= 128.01


def test_multi_treatment_pdf_renders_string_line_fees():
    now = datetime.now(timezone.utc)
    visit = TreatmentTransactionRead(
        id=uuid4(),
        created_at=now,
        updated_at=now,
        version=1,
        clinic_id=uuid4(),
        treatment_id=uuid4(),
        created_by=uuid4(),
        transaction_date=date(2026, 9, 22),
        quantity=1,
        amount=Decimal("13000.00"),
        patient_id=uuid4(),
        serial_no=12,
        sub_treatment="RCT & Filling",
        details={
            "kind": "visit",
            "items": [
                {
                    "id": str(uuid4()),
                    "treatment_name": "RCT",
                    "sub_treatment": "RCT",
                    "tooth_number": "16",
                    "canals": 3,
                    "amount": "8000.00",
                    "notes": "Upper molar <urgent>",
                },
                {
                    "id": str(uuid4()),
                    "treatment_name": "Dental Filling",
                    "sub_treatment": "Composite Filling",
                    "tooth_number": "24",
                    "amount": "5000.00",
                },
            ],
        },
        patient_name="Ali Khan",
        patient_phone="0300-1234567",
        treatment_name="RCT",
        category_name="Endodontics",
    )
    pdf = render_treatment_pdf(visit, clinic_name="Nabi Dental", currency="PKR")
    assert pdf[:4] == b"%PDF"
    text = _pdf_text(pdf)
    assert "1. RCT" in text
    assert "2. Composite Filling" in text
    assert "0300-1234567" in text
    assert "Clinical details" not in text
    assert "Sub-treatment" not in text


def test_item_rows_skip_empty_and_duplicate_labels():
    rows = _item_dental_rows(
        {
            "sub_treatment": "Root Canal Treatment (RCT)",
            "tooth_number": "16",
            "canals": 3,
            "amount": "8000.00",
            "notes": "Watch bite",
        },
        "PKR",
    )
    labels = [label for label, _ in rows]
    assert labels == ["Tooth / teeth", "Canals", "Fee", "Notes"]
    assert "Treatment" not in labels
    assert "Clinical details" not in labels


def test_pdf_theme_uses_medical_blue():
    assert PRIMARY.hexval().upper() == "0X2F80ED"
    assert PRIMARY_DARK.hexval().upper() == "0X1B6CDE"


def test_clinic_pdf_drops_sub_treatment_column():
    report = ClinicReport(
        period=PeriodWindow(from_date=date(2026, 9, 1), to_date=date(2026, 9, 30)),
        currency="PKR",
        total_income=Decimal("8000.00"),
        total_expenses=Decimal("1000.00"),
        total_lab_charges=Decimal("1500.00"),
        profit=Decimal("5500.00"),
        income_count=1,
        expense_count=0,
        lab_charge_count=1,
        patient_count=1,
        income_by_treatment=[NamedAmount(name="Scaling", amount=Decimal("8000.00"))],
        expenses_by_category=[],
        income_lines=[
            ReportLine(
                entry_date=date(2026, 9, 2),
                name="Dental Treatments",
                amount=Decimal("8000.00"),
                serial_no=12,
                patient_name="Ali Khan",
                sub_treatment="Scaling",
                tooth="11",
            )
        ],
        expense_lines=[],
        lab_charge_lines=[
            ReportLine(
                entry_date=date(2026, 9, 3),
                name="Smile Ceramics",
                amount=Decimal("1500.00"),
                serial_no=12,
                patient_name="Ali Khan",
                sub_treatment="Zirconia Crown",
            )
        ],
        timeline=[],
    )
    pdf = render_clinic_pdf(report, clinic_name="Nabi Dental")
    text = _pdf_text(pdf)
    assert pdf[:4] == b"%PDF"
    assert "Sub-treatment" not in text
    assert "Scaling" in text
    assert "Income" in text
    assert "Profit / loss" in text
    assert "Lab charges" in text
    assert "Smile Ceramics" in text
