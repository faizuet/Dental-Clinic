from datetime import datetime, timezone
from io import BytesIO

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.schemas.report import ClinicReport, HomeReport
from app.utils.dates import serialize_datetime
from app.utils.money import format_money


def render_clinic_pdf(report: ClinicReport, *, clinic_name: str) -> bytes:
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, title=f"{clinic_name} clinic report")
    styles = getSampleStyleSheet()
    story = [
        Paragraph(clinic_name, styles["Title"]),
        Paragraph("Clinic Finance Report", styles["Heading2"]),
        Paragraph(
            f"Period: {report.period.from_date} to {report.period.to_date} (inclusive)",
            styles["Normal"],
        ),
        Paragraph(f"Generated: {serialize_datetime(datetime.now(timezone.utc))}", styles["Normal"]),
        Spacer(1, 12),
        _summary_table(
            [
                ["Currency", report.currency],
                ["Total income", format_money(report.total_income)],
                ["Total clinic expenses", format_money(report.total_expenses)],
                ["Profit / loss", format_money(report.profit)],
            ]
        ),
        Spacer(1, 16),
        Paragraph("Income by treatment", styles["Heading3"]),
        _named_table(report.income_by_treatment),
        Spacer(1, 12),
        Paragraph("Expenses by category", styles["Heading3"]),
        _named_table(report.expenses_by_category),
    ]
    doc.build(story)
    return buffer.getvalue()


def render_home_pdf(report: HomeReport, *, clinic_name: str) -> bytes:
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, title=f"{clinic_name} home report")
    styles = getSampleStyleSheet()
    story = [
        Paragraph(clinic_name, styles["Title"]),
        Paragraph("Home Finance Report", styles["Heading2"]),
        Paragraph(
            f"Period: {report.period.from_date} to {report.period.to_date} (inclusive)",
            styles["Normal"],
        ),
        Paragraph(f"Generated: {serialize_datetime(datetime.now(timezone.utc))}", styles["Normal"]),
        Spacer(1, 12),
        _summary_table(
            [
                ["Currency", report.currency],
                ["Total spending", format_money(report.total_expenses)],
                ["Budget", format_money(report.budget)],
                ["Remaining", format_money(report.remaining)],
                ["Percentage used", report.percentage_used if report.percentage_used is not None else "n/a"],
            ]
        ),
        Spacer(1, 16),
        Paragraph("Spending by category", styles["Heading3"]),
        _named_table(report.expenses_by_category),
    ]
    doc.build(story)
    return buffer.getvalue()


def _summary_table(rows: list[list[str]]) -> Table:
    table = Table(rows, colWidths=[200, 250])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#F3E8FF")),
                ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("PADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def _named_table(items) -> Table:
    data = [["Name", "Amount"]] + [[item.name, format_money(item.amount)] for item in items]
    if len(data) == 1:
        data.append(["None", "0.00"])
    table = Table(data, colWidths=[300, 150])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#7C3AED")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("PADDING", (0, 0), (-1, -1), 6),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#E5E7EB")),
            ]
        )
    )
    return table
