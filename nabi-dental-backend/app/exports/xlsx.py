from io import BytesIO

from openpyxl import Workbook

from app.schemas.report import ClinicReport, HomeReport
from app.utils.money import format_money


def render_clinic_xlsx(report: ClinicReport, *, clinic_name: str) -> bytes:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Clinic Report"
    sheet.append([clinic_name])
    sheet.append(["Clinic Finance Report"])
    sheet.append(["From", str(report.period.from_date)])
    sheet.append(["To", str(report.period.to_date)])
    sheet.append(["Currency", report.currency])
    sheet.append([])
    sheet.append(["Total income", format_money(report.total_income)])
    sheet.append(["Total clinic expenses", format_money(report.total_expenses)])
    sheet.append(["Profit / loss", format_money(report.profit)])
    sheet.append([])
    sheet.append(["Income by treatment", "Amount"])
    for item in report.income_by_treatment:
        sheet.append([item.name, format_money(item.amount)])
    sheet.append([])
    sheet.append(["Expenses by category", "Amount"])
    for item in report.expenses_by_category:
        sheet.append([item.name, format_money(item.amount)])
    return _save(workbook)


def render_home_xlsx(report: HomeReport, *, clinic_name: str) -> bytes:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Home Report"
    sheet.append([clinic_name])
    sheet.append(["Home Finance Report"])
    sheet.append(["From", str(report.period.from_date)])
    sheet.append(["To", str(report.period.to_date)])
    sheet.append(["Currency", report.currency])
    sheet.append([])
    sheet.append(["Total spending", format_money(report.total_expenses)])
    sheet.append(["Budget", format_money(report.budget)])
    sheet.append(["Remaining", format_money(report.remaining)])
    sheet.append(["Percentage used", str(report.percentage_used) if report.percentage_used is not None else "n/a"])
    sheet.append([])
    sheet.append(["Spending by category", "Amount"])
    for item in report.expenses_by_category:
        sheet.append([item.name, format_money(item.amount)])
    return _save(workbook)


def _save(workbook: Workbook) -> bytes:
    buffer = BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()
