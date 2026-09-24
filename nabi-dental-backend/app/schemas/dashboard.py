from datetime import date
from decimal import Decimal

from pydantic import field_serializer

from app.utils.money import format_money
from app.utils.pagination import APIModel


class ClinicDashboard(APIModel):
    period: str
    from_date: date
    to_date: date
    currency: str
    total_income: Decimal
    total_expenses: Decimal
    profit: Decimal

    @field_serializer("total_income", "total_expenses", "profit")
    def serialize_money(self, value: Decimal) -> str:
        return format_money(value)


class HomeDashboard(APIModel):
    period: str
    from_date: date
    to_date: date
    currency: str
    total_expenses: Decimal
    budget: Decimal
    remaining: Decimal
    percentage_used: Decimal | None
    budget_source: str

    @field_serializer("total_expenses", "budget", "remaining")
    def serialize_money(self, value: Decimal) -> str:
        return format_money(value)

    @field_serializer("percentage_used")
    def serialize_percentage(self, value: Decimal | None) -> str | None:
        if value is None:
            return None
        return f"{value:.2f}"
