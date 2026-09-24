from datetime import date
from decimal import Decimal

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.repositories.totals import TotalsRepository
from app.schemas.dashboard import ClinicDashboard, HomeDashboard
from app.services.home_expense_service import HomeExpenseService
from app.utils.dates import month_bounds, resolve_period_range
from app.utils.money import parse_money


def percentage_used(spent: Decimal, budget: Decimal) -> Decimal | None:
    if budget == 0:
        return None
    return (spent / budget * Decimal("100")).quantize(Decimal("0.01"))


class DashboardService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.totals = TotalsRepository(session)
        self.home_service = HomeExpenseService(session)

    async def clinic(
        self,
        user: User,
        *,
        period: str,
        value_date: date | None,
        from_date: date | None,
        to_date: date | None,
    ) -> ClinicDashboard:
        start, end = resolve_period_range(
            period=period,
            value_date=value_date,
            from_date=from_date,
            to_date=to_date,
            tz_name=user.clinic.timezone,
        )
        income = await self.totals.treatment_income_total(user.clinic_id, start, end)
        expenses = await self.totals.clinic_expense_total(user.clinic_id, start, end)
        return ClinicDashboard(
            period=period,
            from_date=start,
            to_date=end,
            currency=user.clinic.currency,
            total_income=income,
            total_expenses=expenses,
            profit=parse_money(income - expenses),
        )

    async def home(
        self,
        user: User,
        *,
        period: str,
        value_date: date | None,
        from_date: date | None,
        to_date: date | None,
    ) -> HomeDashboard:
        start, end = resolve_period_range(
            period=period,
            value_date=value_date,
            from_date=from_date,
            to_date=to_date,
            tz_name=user.clinic.timezone,
        )
        spent = await self.totals.home_expense_total(user.id, start, end)
        month_start, _ = month_bounds(end.year, end.month)
        budget, source = await self.home_service.resolve_budget_amount(user, month_start.year, month_start.month)
        remaining = parse_money(budget - spent)
        return HomeDashboard(
            period=period,
            from_date=start,
            to_date=end,
            currency=user.clinic.currency,
            total_expenses=spent,
            budget=budget,
            remaining=remaining,
            percentage_used=percentage_used(spent, budget),
            budget_source=source,
        )
