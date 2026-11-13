from datetime import date
from decimal import Decimal

from pydantic import field_serializer

from app.utils.money import format_money
from app.utils.pagination import APIModel


class PeriodWindow(APIModel):
    from_date: date
    to_date: date


class NamedAmount(APIModel):
    id: str | None = None
    name: str
    amount: Decimal

    @field_serializer("amount")
    def serialize_amount(self, value: Decimal) -> str:
        return format_money(value)


class TimelinePoint(APIModel):
    period: str
    income: Decimal | None = None
    expenses: Decimal | None = None
    profit: Decimal | None = None

    @field_serializer("income", "expenses", "profit")
    def serialize_money(self, value: Decimal | None) -> str | None:
        if value is None:
            return None
        return format_money(value)


class ReportLine(APIModel):
    entry_date: date
    name: str
    detail: str | None = None
    amount: Decimal
    serial_no: int | None = None
    patient_name: str | None = None
    sub_treatment: str | None = None
    tooth: str | None = None
    details_text: str | None = None

    @field_serializer("amount")
    def serialize_amount(self, value: Decimal) -> str:
        return format_money(value)


class ClinicReport(APIModel):
    period: PeriodWindow
    currency: str
    total_income: Decimal
    total_expenses: Decimal
    profit: Decimal
    income_count: int = 0
    expense_count: int = 0
    patient_count: int = 0
    income_by_treatment: list[NamedAmount]
    expenses_by_category: list[NamedAmount]
    income_lines: list[ReportLine] = []
    expense_lines: list[ReportLine] = []
    timeline: list[TimelinePoint]

    @field_serializer("total_income", "total_expenses", "profit")
    def serialize_money(self, value: Decimal) -> str:
        return format_money(value)


class HomeReport(APIModel):
    period: PeriodWindow
    currency: str
    total_expenses: Decimal
    expense_count: int = 0
    expenses_by_category: list[NamedAmount]
    expense_lines: list[ReportLine] = []
    budget: Decimal
    remaining: Decimal
    percentage_used: Decimal | None
    budget_source: str
    timeline: list[TimelinePoint]

    @field_serializer("total_expenses", "budget", "remaining")
    def serialize_home_money(self, value: Decimal) -> str:
        return format_money(value)

    @field_serializer("percentage_used")
    def serialize_percentage(self, value: Decimal | None) -> str | None:
        if value is None:
            return None
        return f"{value:.2f}"
