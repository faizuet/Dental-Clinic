from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.graphics.shapes import Drawing, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.schemas.report import ClinicReport, ConstructionReport, HomeReport, NamedAmount
from app.schemas.treatment_transaction import TreatmentTransactionRead
from app.utils.treatment_details import (
    resolved_sub_treatment,
    tooth_label,
    visit_items,
)
from app.utils.dates import format_display_date, format_display_date_range
from app.utils.money import format_money, format_quantity, parse_money

PRIMARY = colors.HexColor("#2F80ED")
PRIMARY_DARK = colors.HexColor("#1B6CDE")
PRIMARY_SOFT = colors.HexColor("#E8F2FF")
BACKGROUND = colors.HexColor("#F3F7FF")
TEXT = colors.HexColor("#1B2430")
MUTED = colors.HexColor("#7A8699")
BORDER = colors.HexColor("#E4ECF6")
ROW_ALT = colors.HexColor("#F7FAFF")
SUCCESS = colors.HexColor("#2F9E6A")
DANGER = colors.HexColor("#D64545")
WHITE = colors.white


def render_clinic_pdf(report: ClinicReport, *, clinic_name: str) -> bytes:
    generated = _generated_label()
    title = "Clinic Treatment Report"
    story = [
        *_metric_cards(
            [
                ("Income", _money(report.total_income, report.currency), SUCCESS),
                ("Clinic expenses", _money(report.total_expenses, report.currency), TEXT),
                ("Profit / loss", _money(report.profit, report.currency), DANGER if report.profit < 0 else SUCCESS),
            ]
        ),
        *_kv_section(
            "Report details",
            [
                ("Currency", report.currency),
                ("Patients treated", str(report.patient_count)),
                ("Treatments", str(report.income_count)),
                ("Expense entries", str(report.expense_count)),
            ],
        ),
        *_named_section("Income by treatment", report.income_by_treatment, report.currency),
        *_named_section("Expenses by category", report.expenses_by_category, report.currency),
        *_chart_section("Expense mix", report.expenses_by_category),
        *_line_section(
            "Treatment records",
            ["Sr.", "Patient", "Date", "Treatment", "Tooth / teeth", "Details", "Fee"],
            [
                [
                    str(item.serial_no or "—"),
                    item.patient_name or "Walk-in",
                    format_display_date(item.entry_date),
                    item.sub_treatment or item.name,
                    item.tooth or "—",
                    item.details_text or item.detail or "—",
                    _money(item.amount, report.currency),
                ]
                for item in report.income_lines
            ],
            [28, 82, 52, 100, 64, 86, 60],
            [6],
        ),
        *_line_section(
            "Clinic expenses",
            ["Date", "Category", "Notes", "Amount"],
            [
                [format_display_date(item.entry_date), item.name, item.detail or "—", _money(item.amount, report.currency)]
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
        accent=PRIMARY,
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
    items = visit_items(details)
    multi = isinstance(details.get("items"), list) and len(items) > 0
    sub_treatment = resolved_sub_treatment(
        sub_treatment=visit.sub_treatment,
        details=details,
        treatment_name=visit.treatment_name,
    )
    info_rows = [
        ("Sr. No.", str(visit.serial_no or "—")),
        ("Patient", visit.patient_name or "Walk-in"),
    ]
    if visit.patient_phone:
        info_rows.append(("Phone", visit.patient_phone))
    info_rows.extend(
        [
            ("Date", format_display_date(visit.transaction_date)),
            (
                "Treatments" if multi else "Treatment",
                f"{len(items)} treatments" if multi else (sub_treatment or visit.treatment_name or "—"),
            ),
            ("Total fee" if multi else "Fee", _money(visit.amount, currency)),
        ]
    )
    story = [*_kv_section("Patient information", info_rows)]
    if multi:
        for index, item in enumerate(items, start=1):
            name = str(item.get("sub_treatment") or item.get("treatment_name") or f"Treatment {index}")
            story.extend(_kv_section(f"{index}. {name}", _item_dental_rows(item, currency)))
    else:
        name = sub_treatment or visit.treatment_name or "Treatment"
        dental_rows = _item_dental_rows(
            {
                **details,
                "sub_treatment": name,
                "amount": visit.amount,
                "notes": visit.notes,
            },
            currency,
        )
        story.extend(_kv_section(name, dental_rows or [("Details", "No clinical details recorded.")]))
    story.extend(_treatment_images(image_paths or []))
    return _build(
        story,
        clinic_name=clinic_name,
        title=title,
        generated=generated,
        period=format_display_date(visit.transaction_date),
        accent=PRIMARY,
    )


def _item_dental_rows(item: dict, currency: str) -> list[tuple[str, str]]:
    amount = item.get("amount")
    notes = str(item.get("notes") or "").strip()
    rows = [
        ("Tooth / teeth", tooth_label(item) or ""),
        ("Canals", str(item["canals"]) if item.get("canals") else ""),
        ("Length", f"{item['length_mm']} mm" if item.get("length_mm") else ""),
        ("Material", str(item["material"]) if item.get("material") else ""),
        ("Units", str(item["units"]) if item.get("units") else ""),
        ("Arch / type", str(item.get("arch") or item.get("denture_type") or "").replace("_", " ").title()),
        ("Scope", str(item.get("scope") or "").replace("_", " ").title()),
        ("Fee", _money(amount, currency) if amount not in (None, "") else ""),
        ("Notes", notes),
    ]
    return [(label, value) for label, value in rows if value and value not in {"—", "None"}]


def _kv_section(title: str, rows: list[tuple[str, str]]) -> list:
    styles = _styles()
    safe_rows = rows or [("Details", "—")]
    table = Table(
        [
            [Paragraph(_pdf_text(label), styles["kvLabel"]), Paragraph(_pdf_text(value), styles["kvValue"])]
            for label, value in safe_rows
        ],
        colWidths=[140, 332],
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), PRIMARY_SOFT),
                ("BACKGROUND", (1, 0), (1, -1), WHITE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("BOX", (0, 0), (-1, -1), 0.4, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, BORDER),
            ]
        )
    )
    return [Paragraph(title, styles["section"]), table, Spacer(1, 12)]


def _treatment_images(image_paths: list[tuple[str, str]]) -> list:
    styles = _styles()
    frames = []
    for label, path in image_paths:
        file_path = Path(path)
        if not file_path.is_file():
            continue
        try:
            image = Image(str(file_path))
            image.drawWidth, image.drawHeight = _fit_image(image.imageWidth, image.imageHeight, 190, 128)
            caption = Paragraph((label or "X-ray").replace("_", " ").upper(), styles["meta"])
            frame = Table([[caption], [image]], colWidths=[220])
            frame.setStyle(
                TableStyle(
                    [
                        ("BACKGROUND", (0, 0), (-1, 0), PRIMARY_SOFT),
                        ("BACKGROUND", (0, 1), (-1, 1), WHITE),
                        ("BOX", (0, 0), (-1, -1), 0.4, BORDER),
                        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                        ("VALIGN", (0, 1), (-1, 1), "MIDDLE"),
                        ("LEFTPADDING", (0, 0), (-1, -1), 8),
                        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                        ("TOPPADDING", (0, 0), (0, 0), 6),
                        ("BOTTOMPADDING", (0, 0), (0, 0), 4),
                        ("TOPPADDING", (0, 1), (0, 1), 8),
                        ("BOTTOMPADDING", (0, 1), (0, 1), 8),
                    ]
                )
            )
            frames.append(frame)
        except Exception:
            continue
    if not frames:
        return []
    rows: list[list] = []
    for index in range(0, len(frames), 2):
        pair = frames[index : index + 2]
        if len(pair) == 1:
            pair.append("")
        rows.append(pair)
    grid = Table(rows, colWidths=[236, 236])
    grid.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return [Paragraph("X-ray images", styles["section"]), grid, Spacer(1, 8)]


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
        *_metric_cards(
            [
                ("Spending", _money(report.total_expenses, report.currency), TEXT),
                ("Budget", _money(report.budget, report.currency), PRIMARY_DARK),
                ("Remaining", _money(report.remaining, report.currency), SUCCESS if report.remaining >= 0 else DANGER),
            ]
        ),
        *_kv_section(
            "Report details",
            [
                ("Currency", report.currency),
                ("Transactions", str(report.expense_count)),
                ("Budget used", used),
            ],
        ),
        *_named_section("Spending by category", report.expenses_by_category, report.currency),
        *_chart_section("Category mix", report.expenses_by_category),
        *_line_section(
            "Home expenses",
            ["Date", "Category", "Notes", "Amount"],
            [
                [format_display_date(item.entry_date), item.name, item.detail or "—", _money(item.amount, report.currency)]
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
        accent=PRIMARY,
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
            format_display_date(item.purchase_date),
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
        *_metric_cards(
            [
                ("Total spend", _money(report.total_expenses, report.currency), TEXT),
                ("Purchases", str(report.purchase_count), PRIMARY_DARK),
                ("Highest category", report.top_categories[0].name if report.top_categories else "—", TEXT),
            ]
        ),
        *_kv_section(
            "Report details",
            [
                ("Currency", report.currency),
                ("Categories used", str(len(report.expenses_by_category))),
                ("Suppliers", str(len(report.expenses_by_supplier))),
            ],
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
        accent=PRIMARY_DARK,
    )


def _build(story, *, clinic_name: str, title: str, generated: str, period: str, accent) -> bytes:
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        title=f"{clinic_name} {title}",
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=26 * mm,
        bottomMargin=18 * mm,
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
    canvas.setFillColor(BACKGROUND)
    canvas.rect(0, 0, width, height, fill=1, stroke=0)
    canvas.setFillColor(accent)
    canvas.rect(0, height - 54, width, 54, fill=1, stroke=0)
    canvas.setFillColor(PRIMARY_DARK)
    canvas.rect(0, height - 58, width, 4, fill=1, stroke=0)
    canvas.setFillColor(WHITE)
    canvas.roundRect(16, height - 40, 24, 24, 6, fill=1, stroke=0)
    canvas.setFillColor(accent)
    canvas.setFont("Helvetica-Bold", 12)
    canvas.drawCentredString(28, height - 33, "N")
    canvas.setFillColor(WHITE)
    canvas.setFont("Helvetica-Bold", 12)
    canvas.drawString(48, height - 22, clinic_name)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(48, height - 36, f"{title}  ·  {period}")
    canvas.setFillColor(PRIMARY_SOFT)
    canvas.rect(0, 0, width, 30, fill=1, stroke=0)
    canvas.setFillColor(PRIMARY)
    canvas.rect(0, 30, width, 2, fill=1, stroke=0)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(16 * mm, 12, f"{clinic_name}  ·  {generated}")
    canvas.drawRightString(width - 16 * mm, 12, f"Page {doc.page}")
    canvas.restoreState()


def _period_label(from_date, to_date) -> str:
    return f"{format_display_date_range(from_date, to_date)} (inclusive)"


def _metric_cards(items: list[tuple[str, str, object]]) -> list:
    styles = _styles()
    cards = []
    card_width = 154
    for label, value, color in items:
        value_style = ParagraphStyle(
            f"MetricValue{len(cards)}",
            parent=styles["summaryValue"],
            textColor=color,
            fontSize=11,
            leading=14,
        )
        inner = Table(
            [
                [Paragraph(_pdf_text(label), styles["summaryLabel"])],
                [Paragraph(_pdf_text(value), value_style)],
            ],
            colWidths=[card_width],
        )
        inner.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), PRIMARY_SOFT),
                    ("BOX", (0, 0), (-1, -1), 0.4, BORDER),
                    ("LEFTPADDING", (0, 0), (-1, -1), 10),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                    ("TOPPADDING", (0, 0), (0, 0), 8),
                    ("BOTTOMPADDING", (0, -1), (0, -1), 8),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ]
            )
        )
        cards.append(inner)
    table = Table([cards], colWidths=[card_width + 8] * len(cards))
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-2, -1), 8),
                ("RIGHTPADDING", (-1, 0), (-1, -1), 0),
            ]
        )
    )
    return [table, Spacer(1, 12)]


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
    data = [[Paragraph(_pdf_text(header), styles["headerCell"]) for header in headers]]
    if not rows:
        data.append(
            [Paragraph("No records found for the selected date range.", styles["cell"])] + [""] * (len(headers) - 1)
        )
    else:
        for row in rows:
            styled = []
            for index, value in enumerate(row):
                style = styles["value"] if index in amount_cols else styles["cell"]
                styled.append(Paragraph(_pdf_text(value), style))
            data.append(styled)
    table = Table(data, colWidths=widths, repeatRows=1)
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), PRIMARY_DARK),
        ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("BACKGROUND", (0, 1), (-1, -1), WHITE),
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
        drawing.add(Rect(130, y + 2, bar_w, 9, fillColor=PRIMARY, strokeColor=None))
    return [Paragraph(title, styles["section"]), drawing, Spacer(1, 10)]


def _timeline_section(points, currency: str, *, include_income: bool) -> list:
    if include_income:
        rows = [
            [
                format_display_date(item.period) if "-" in str(item.period) else item.period,
                _money(item.income, currency) if item.income is not None else "—",
                _money(item.expenses, currency) if item.expenses is not None else "—",
                _money(item.profit, currency) if item.profit is not None else "—",
            ]
            for item in points
        ]
        return _line_section("Period summary", ["Period", "Income", "Expenses", "Profit"], rows, [140, 110, 110, 112], [1, 2, 3])
    rows = [[format_display_date(item.period) if "-" in str(item.period) else item.period, _money(item.expenses, currency) if item.expenses is not None else "—"] for item in points]
    return _line_section("Monthly / period spending", ["Period", "Amount"], rows, [280, 192], [1])


def _pdf_text(value) -> str:
    if value is None:
        return "—"
    return escape(str(value))


def _money(value, currency: str) -> str:
    if value is None or value == "":
        return f"{currency} 0.00"
    return f"{currency} {format_money(parse_money(value))}"


def _generated_label() -> str:
    now = datetime.now(timezone.utc)
    return f"{format_display_date(now)} {now.strftime('%H:%M:%S')} UTC"


def _styles():
    base = getSampleStyleSheet()
    return {
        "reportTitle": ParagraphStyle(
            "ReportTitle",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=16,
            textColor=PRIMARY_DARK,
            spaceAfter=2,
            leading=20,
        ),
        "section": ParagraphStyle(
            "Section",
            parent=base["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=11,
            textColor=PRIMARY_DARK,
            spaceBefore=4,
            spaceAfter=6,
        ),
        "meta": ParagraphStyle("Meta", parent=base["Normal"], fontSize=8, textColor=MUTED),
        "cell": ParagraphStyle(
            "Cell",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=TEXT,
            alignment=TA_LEFT,
        ),
        "kvLabel": ParagraphStyle(
            "KvLabel",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=11,
            textColor=MUTED,
            alignment=TA_LEFT,
        ),
        "kvValue": ParagraphStyle(
            "KvValue",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=12,
            textColor=TEXT,
            alignment=TA_LEFT,
        ),
        "value": ParagraphStyle(
            "Value",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=12,
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
