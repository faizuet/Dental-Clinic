from datetime import date
from decimal import Decimal

from pydantic import field_serializer

from app.utils.money import format_money, format_quantity
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

    @field_serializer("amount")
    def serialize_amount(self, value: Decimal) -> str:
        return format_money(value)


class QuantityAmount(APIModel):
    name: str
    quantity: Decimal
    unit: str
    amount: Decimal

    @field_serializer("amount")
    def serialize_amount(self, value: Decimal) -> str:
        return format_money(value)

    @field_serializer("quantity")
    def serialize_quantity(self, value: Decimal) -> str:
        return format_quantity(value)


class ConstructionPurchaseLine(APIModel):
    purchase_date: date
    material_name: str
    category_name: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    amount: Decimal
    supplier: str | None = None

    @field_serializer("amount", "unit_price")
    def serialize_money(self, value: Decimal) -> str:
        return format_money(value)

    @field_serializer("quantity")
    def serialize_quantity(self, value: Decimal) -> str:
        return format_quantity(value)


class ClinicReport(APIModel):
    period: PeriodWindow
    currency: str
    total_income: Decimal
    total_expenses: Decimal
    profit: Decimal
    income_count: int = 0
    expense_count: int = 0
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


class ConstructionReport(APIModel):
    period: PeriodWindow
    currency: str
    total_expenses: Decimal
    purchase_count: int
    expenses_by_category: list[NamedAmount]
    spending_by_material: list[QuantityAmount]
    expenses_by_supplier: list[NamedAmount]
    top_materials: list[NamedAmount]
    top_categories: list[NamedAmount]
    purchases: list[ConstructionPurchaseLine]
    timeline: list[TimelinePoint]

    @field_serializer("total_expenses")
    def serialize_total_expenses(self, value: Decimal) -> str:
        return format_money(value)
