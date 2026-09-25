from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

from reportlab.graphics.shapes import Drawing, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.schemas.report import ClinicReport, ConstructionReport, HomeReport, NamedAmount
from app.schemas.treatment_transaction import TreatmentTransactionRead
from app.utils.treatment_details import clinical_summary, tooth_label
from app.utils.dates import serialize_datetime
from app.utils.money import format_money, format_quantity

PURPLE = colors.HexColor("#7C3AED")
PURPLE_SOFT = colors.HexColor("#F3E8FF")
TEAL = colors.HexColor("#0F766E")
TEXT = colors.HexColor("#1F2937")
MUTED = colors.HexColor("#6B7280")
BORDER = colors.HexColor("#E5E7EB")
ROW_ALT = colors.HexColor("#FAF7FF")
WHITE = colors.white


def render_clinic_pdf(report: ClinicReport, *, clinic_name: str) -> bytes:
    generated = _generated_label()
    title = "Clinic Treatment Report"
    story = [
        *_summary_block(
            [
                ("Currency", report.currency),
                ("Patients treated", str(report.patient_count)),
                ("Treatments", str(report.income_count)),
                ("Expense entries", str(report.expense_count)),
                ("Total treatment income", _money(report.total_income, report.currency)),
                ("Total clinic expenses", _money(report.total_expenses, report.currency)),
                ("Profit / loss", _money(report.profit, report.currency)),
            ]
        ),
        *_named_section("Income by treatment", report.income_by_treatment, report.currency),
        *_named_section("Expenses by category", report.expenses_by_category, report.currency),
        *_chart_section("Expense mix", report.expenses_by_category),
        *_line_section(
            "Treatment records",
            ["Sr.", "Patient", "Date", "Treatment", "Sub-treatment", "Tooth / teeth", "Details", "Fee"],
            [
                [
                    str(item.serial_no or "—"),
                    item.patient_name or "Walk-in",
                    str(item.entry_date),
                    item.name,
                    item.sub_treatment or "—",
                    item.tooth or "—",
                    item.details_text or item.detail or "—",
                    _money(item.amount, report.currency),
                ]
                for item in report.income_lines
            ],
            [28, 70, 52, 62, 58, 58, 80, 64],
            [7],
        ),
        *_line_section(
            "Clinic expenses",
            ["Date", "Category", "Notes", "Amount"],
            [
                [str(item.entry_date), item.name, item.detail or "—", _money(item.amount, report.currency)]
                for item in report.expense_lines
            ],
            [72, 150, 170, 80],
            [3],
        ),
        *_timeline_section(report.timeline, report.currency, include_income=True),
    ]
    return _build(
        story,
        clinic_name=clinic_name,
        title=title,
        generated=generated,
        period=_period_label(report.period.from_date, report.period.to_date),
        accent=PURPLE,
    )


def render_treatment_pdf(
    visit: TreatmentTransactionRead,
    *,
    clinic_name: str,
    currency: str,
    image_paths: list[tuple[str, str]] | None = None,
) -> bytes:
    generated = _generated_label()
    title = "Patient Treatment Record"
    details = visit.details or {}
    tooth = tooth_label(details) or "—"
    summary = clinical_summary(details, visit.sub_treatment) or "—"
    info_rows = [
        ("Sr. No.", str(visit.serial_no or "—")),
        ("Patient", visit.patient_name or "Walk-in"),
        ("Treatment date", str(visit.transaction_date)),
        ("Main treatment", visit.treatment_name or visit.category_name or "Treatment"),
        ("Sub-treatment", visit.sub_treatment or "—"),
        ("Fee", _money(visit.amount, currency)),
    ]
    dental_rows = [
        ("Tooth / teeth", tooth),
        ("Canals", str(details["canals"]) if details.get("canals") else "—"),
        ("Length", f"{details['length_mm']} mm" if details.get("length_mm") else "—"),
        ("Material", str(details["material"]) if details.get("material") else "—"),
        ("Units", str(details["units"]) if details.get("units") else "—"),
        ("Arch / type", str(details.get("arch") or details.get("denture_type") or "—").replace("_", " ").title()),
        ("Scope", str(details.get("scope") or "—").replace("_", " ").title()),
        ("Clinical details", summary),
    ]
    dental_rows = [row for row in dental_rows if row[1] not in {"—", "—".title()} or row[0] in {"Tooth / teeth", "Clinical details"}]
    story = [
        *_kv_section("Patient information", info_rows),
        *_kv_section("Dental information", dental_rows),
        *_kv_section("Treatment notes", [("Notes", visit.notes or "No notes recorded.")]),
    ]
    images = _treatment_images(image_paths or [])
    if images:
        story.append(Paragraph("X-ray images", _styles()["section"]))
        story.extend(images)
    else:
        story.extend(_kv_section("X-ray images", [("Attachments", "No X-ray attached.")]))
    return _build(
        story,
        clinic_name=clinic_name,
        title=title,
        generated=generated,
        period=str(visit.transaction_date),
        accent=PURPLE,
    )


def _kv_section(title: str, rows: list[tuple[str, str]]) -> list:
    styles = _styles()
    table = Table(
        [[Paragraph(label, styles["cell"]), Paragraph(value, styles["cell"])] for label, value in rows],
        colWidths=[140, 332],
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), PURPLE_SOFT),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("BOX", (0, 0), (-1, -1), 0.4, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, BORDER),
            ]
        )
    )
    return [Paragraph(title, styles["section"]), table, Spacer(1, 12)]


def _treatment_images(image_paths: list[tuple[str, str]]) -> list:
    styles = _styles()
    blocks = []
    for label, path in image_paths:
        file_path = Path(path)
        if not file_path.is_file():
            continue
        try:
            image = Image(str(file_path))
            image.drawWidth, image.drawHeight = _fit_image(image.imageWidth, image.imageHeight, 420, 260)
            caption = Paragraph((label or "X-ray").replace("_", " ").title(), styles["meta"])
            blocks.extend([KeepTogether([caption, image]), Spacer(1, 10)])
        except Exception:
            continue
    return blocks


def _fit_image(width: float, height: float, max_w: float, max_h: float) -> tuple[float, float]:
    if width <= 0 or height <= 0:
        return max_w, max_h / 2
    ratio = min(max_w / width, max_h / height)
    return width * ratio, height * ratio


def render_home_pdf(report: HomeReport, *, clinic_name: str) -> bytes:
    generated = _generated_label()
    title = "Home Expense Report"
    used = f"{report.percentage_used:.2f}%" if report.percentage_used is not None else "n/a"
    story = [
        *_summary_block(
            [
                ("Currency", report.currency),
                ("Transactions", str(report.expense_count)),
                ("Total spending", _money(report.total_expenses, report.currency)),
                ("Budget", _money(report.budget, report.currency)),
                ("Remaining", _money(report.remaining, report.currency)),
                ("Budget used", used),
            ]
        ),
        *_named_section("Spending by category", report.expenses_by_category, report.currency),
        *_chart_section("Category mix", report.expenses_by_category),
        *_line_section(
            "Home expenses",
            ["Date", "Category", "Notes", "Amount"],
            [
                [str(item.entry_date), item.name, item.detail or "—", _money(item.amount, report.currency)]
                for item in report.expense_lines
            ],
            [72, 150, 170, 80],
            [3],
        ),
        *_timeline_section(report.timeline, report.currency, include_income=False),
    ]
    return _build(
        story,
        clinic_name=clinic_name,
        title=title,
        generated=generated,
        period=_period_label(report.period.from_date, report.period.to_date),
        accent=PURPLE,
    )


def render_construction_pdf(report: ConstructionReport, *, clinic_name: str) -> bytes:
    generated = _generated_label()
    title = "Construction Expense Report"
    material_rows = [
        [
            item.name,
            format_quantity(item.quantity),
            item.unit,
            _money(item.amount, report.currency),
        ]
        for item in report.spending_by_material
    ]
    purchase_rows = [
        [
            str(item.purchase_date),
            item.material_name,
            item.category_name,
            f"{format_quantity(item.quantity)} {item.unit}",
            _money(item.unit_price, report.currency),
            _money(item.amount, report.currency),
            item.supplier or "—",
        ]
        for item in report.purchases
    ]
    story = [
        *_summary_block(
            [
                ("Currency", report.currency),
                ("Purchases", str(report.purchase_count)),
                ("Total construction spend", _money(report.total_expenses, report.currency)),
                ("Categories used", str(len(report.expenses_by_category))),
                ("Suppliers", str(len(report.expenses_by_supplier))),
                ("Highest category", report.top_categories[0].name if report.top_categories else "—"),
            ]
        ),
        *_named_section("Expenses by material category", report.expenses_by_category, report.currency),
        *_chart_section("Category mix", report.expenses_by_category),
        *_named_section("Highest-cost materials", report.top_materials, report.currency),
        *_named_section("Supplier spending", report.expenses_by_supplier, report.currency),
        *_line_section(
            "Material-wise quantity and cost",
            ["Material", "Quantity", "Unit", "Total"],
            material_rows,
            [190, 80, 70, 132],
            [3],
        ),
        *_line_section(
            "Purchase history",
            ["Date", "Material", "Category", "Qty", "Unit price", "Total", "Supplier"],
            purchase_rows,
            [62, 88, 72, 58, 70, 70, 72],
            [4, 5],
        ),
        *_timeline_section(report.timeline, report.currency, include_income=False),
    ]
    return _build(
        story,
        clinic_name=clinic_name,
        title=title,
        generated=generated,
        period=_period_label(report.period.from_date, report.period.to_date),
        accent=TEAL,
    )


def _build(story, *, clinic_name: str, title: str, generated: str, period: str, accent) -> bytes:
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        title=f"{clinic_name} {title}",
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=24 * mm,
        bottomMargin=16 * mm,
    )

    def _page(canvas, document):
        _draw_chrome(
            canvas,
            document,
            clinic_name=clinic_name,
            title=title,
            generated=generated,
            period=period,
            accent=accent,
        )

    heading = [
        Paragraph(title, _styles()["reportTitle"]),
        Paragraph(period, _styles()["meta"]),
        Paragraph(f"Generated {generated}", _styles()["meta"]),
        Spacer(1, 10),
    ]
    doc.build(heading + story, onFirstPage=_page, onLaterPages=_page)
    return buffer.getvalue()


def _draw_chrome(canvas, doc, *, clinic_name: str, title: str, generated: str, period: str, accent) -> None:
    width, height = A4
    canvas.saveState()
    canvas.setFillColor(accent)
    canvas.rect(0, height - 52, width, 52, fill=1, stroke=0)
    canvas.setFillColor(WHITE)
    canvas.circle(28, height - 26, 11, fill=1, stroke=0)
    canvas.setFillColor(accent)
    canvas.setFont("Helvetica-Bold", 10)
    canvas.drawCentredString(28, height - 30, "N")
    canvas.setFillColor(WHITE)
    canvas.setFont("Helvetica-Bold", 11)
    canvas.drawString(46, height - 20, clinic_name)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(46, height - 34, f"{title}  ·  {period}")
    canvas.setFillColor(PURPLE_SOFT)
    canvas.rect(0, 0, width, 28, fill=1, stroke=0)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(18 * mm, 11, f"{clinic_name}  ·  {generated}")
    canvas.drawRightString(width - 18 * mm, 11, f"Page {doc.page}")
    canvas.restoreState()


def _period_label(from_date, to_date) -> str:
    return f"{from_date} to {to_date} (inclusive)"


def _summary_block(rows: list[tuple[str, str]]) -> list:
    styles = _styles()
    table_data = [[Paragraph(label, styles["cell"]), Paragraph(value, styles["value"])] for label, value in rows]
    table = Table(table_data, colWidths=[200, 272])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), PURPLE_SOFT),
                ("BACKGROUND", (1, 0), (1, -1), WHITE),
                ("TEXTCOLOR", (0, 0), (-1, -1), TEXT),
                ("FONTNAME", (1, 0), (1, -1), "Helvetica-Bold"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("BOX", (0, 0), (-1, -1), 0.4, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, BORDER),
            ]
        )
    )
    return [
        Paragraph("Financial summary", styles["section"]),
        table,
        Spacer(1, 14),
    ]


def _named_section(title: str, items: list[NamedAmount], currency: str) -> list:
    rows = [[item.name, _money(item.amount, currency)] for item in items]
    return _line_section(title, ["Name", "Amount"], rows, [352, 120], [1])


def _line_section(
    title: str,
    headers: list[str],
    rows: list[list[str]],
    widths: list[float],
    amount_cols: list[int],
) -> list:
    styles = _styles()
    data = [[Paragraph(header, styles["headerCell"]) for header in headers]]
    if not rows:
        data.append(
            [Paragraph("No records found for the selected date range.", styles["cell"])] + [""] * (len(headers) - 1)
        )
    else:
        for row in rows:
            styled = []
            for index, value in enumerate(row):
                style = styles["value"] if index in amount_cols else styles["cell"]
                styled.append(Paragraph(str(value), style))
            data.append(styled)
    table = Table(data, colWidths=widths, repeatRows=1)
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), PURPLE),
        ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("GRID", (0, 0), (-1, -1), 0.25, BORDER),
        ("ALIGN", (0, 1), (-1, -1), "LEFT"),
    ]
    for index in amount_cols:
        commands.append(("ALIGN", (index, 1), (index, -1), "RIGHT"))
    for row_index in range(1, len(data)):
        if row_index % 2 == 0:
            commands.append(("BACKGROUND", (0, row_index), (-1, row_index), ROW_ALT))
    table.setStyle(TableStyle(commands))
    return [KeepTogether([Paragraph(title, styles["section"])]), table, Spacer(1, 12)]


def _chart_section(title: str, items: list[NamedAmount]) -> list:
    if not items:
        return []
    styles = _styles()
    top = items[:6]
    total = sum((item.amount for item in top), start=top[0].amount * 0)
    width = 470
    row_h = 16
    height = 18 + row_h * len(top)
    drawing = Drawing(width, height)
    for index, item in enumerate(top):
        y = height - 16 - (index * row_h)
        ratio = float(item.amount / total) if total else 0
        bar_w = max(8, (width - 170) * min(ratio, 1))
        drawing.add(String(0, y + 3, item.name[:22], fontName="Helvetica", fontSize=8, fillColor=TEXT))
        drawing.add(Rect(130, y + 2, bar_w, 9, fillColor=PURPLE, strokeColor=None))
    return [Paragraph(title, styles["section"]), drawing, Spacer(1, 10)]


def _timeline_section(points, currency: str, *, include_income: bool) -> list:
    if include_income:
        rows = [
            [
                item.period,
                _money(item.income, currency) if item.income is not None else "—",
                _money(item.expenses, currency) if item.expenses is not None else "—",
                _money(item.profit, currency) if item.profit is not None else "—",
            ]
            for item in points
        ]
        return _line_section("Period summary", ["Period", "Income", "Expenses", "Profit"], rows, [140, 110, 110, 112], [1, 2, 3])
    rows = [[item.period, _money(item.expenses, currency) if item.expenses is not None else "—"] for item in points]
    return _line_section("Monthly / period spending", ["Period", "Amount"], rows, [280, 192], [1])


def _money(value, currency: str) -> str:
    return f"{currency} {format_money(value)}"


def _generated_label() -> str:
    return serialize_datetime(datetime.now(timezone.utc)).replace("T", " ").replace("Z", " UTC")


def _styles():
    base = getSampleStyleSheet()
    return {
        "reportTitle": ParagraphStyle(
            "ReportTitle",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=16,
            textColor=TEXT,
            spaceAfter=2,
            leading=20,
        ),
        "section": ParagraphStyle(
            "Section",
            parent=base["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=11,
            textColor=PURPLE,
            spaceBefore=4,
            spaceAfter=6,
        ),
        "meta": ParagraphStyle("Meta", parent=base["Normal"], fontSize=8, textColor=MUTED),
        "cell": ParagraphStyle(
            "Cell",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=11,
            textColor=TEXT,
            alignment=TA_LEFT,
        ),
        "value": ParagraphStyle(
            "Value",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8,
            leading=11,
            textColor=TEXT,
            alignment=TA_RIGHT,
        ),
        "headerCell": ParagraphStyle(
            "HeaderCell",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8,
            textColor=WHITE,
            leading=11,
        ),
        "summaryLabel": ParagraphStyle("SummaryLabel", parent=base["Normal"], fontSize=8, textColor=MUTED),
        "summaryValue": ParagraphStyle(
            "SummaryValue",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=10,
            textColor=TEXT,
        ),
    }
