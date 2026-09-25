from datetime import date
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.exports.pdf import render_clinic_pdf, render_construction_pdf, render_home_pdf
from app.exports.xlsx import render_clinic_xlsx, render_construction_xlsx, render_home_xlsx
from app.models import ClinicExpense, ConstructionPurchase, HomeExpense, TreatmentTransaction, User
from app.repositories.totals import TotalsRepository, _date_bucket
from app.schemas.report import (
    ClinicReport,
    ConstructionPurchaseLine,
    ConstructionReport,
    HomeReport,
    NamedAmount,
    PeriodWindow,
    QuantityAmount,
    ReportLine,
    TimelinePoint,
)
from app.services.dashboard_service import percentage_used
from app.services.home_expense_service import HomeExpenseService
from app.utils.dates import month_bounds, validate_inclusive_range
from app.utils.files import safe_filename
from app.utils.money import parse_money, parse_quantity


class ReportService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.totals = TotalsRepository(session)
        self.home_service = HomeExpenseService(session)

    async def clinic_report(
        self,
        user: User,
        *,
        from_date: date,
        to_date: date,
        group_by: str,
    ) -> ClinicReport:
        validate_inclusive_range(from_date, to_date)
        income = await self.totals.treatment_income_total(user.clinic_id, from_date, to_date)
        expenses = await self.totals.clinic_expense_total(user.clinic_id, from_date, to_date)
        income_rows = await self.totals.income_by_treatment(user.clinic_id, from_date, to_date)
        expense_rows = await self.totals.clinic_expenses_by_category(user.clinic_id, from_date, to_date)
        income_lines = await self.totals.clinic_income_lines(user.clinic_id, from_date, to_date)
        expense_lines = await self.totals.clinic_expense_lines(user.clinic_id, from_date, to_date)
        timeline = await self._clinic_timeline(user.clinic_id, from_date, to_date, group_by)
        return ClinicReport(
            period=PeriodWindow(from_date=from_date, to_date=to_date),
            currency=user.clinic.currency,
            total_income=income,
            total_expenses=expenses,
            profit=parse_money(income - expenses),
            income_count=len(income_lines),
            expense_count=len(expense_lines),
            income_by_treatment=[
                NamedAmount(id=str(row[0]), name=row[1], amount=parse_money(row[2])) for row in income_rows
            ],
            expenses_by_category=[
                NamedAmount(id=str(row[0]), name=row[1], amount=parse_money(row[2])) for row in expense_rows
            ],
            income_lines=[_line(row) for row in income_lines],
            expense_lines=[_line(row) for row in expense_lines],
            timeline=timeline,
        )

    async def home_report(
        self,
        user: User,
        *,
        from_date: date,
        to_date: date,
        group_by: str,
    ) -> HomeReport:
        validate_inclusive_range(from_date, to_date)
        spent = await self.totals.home_expense_total(user.id, from_date, to_date)
        category_rows = await self.totals.home_expenses_by_category(user.id, from_date, to_date)
        expense_lines = await self.totals.home_expense_lines(user.id, from_date, to_date)
        month_start, _ = month_bounds(to_date.year, to_date.month)
        budget, source = await self.home_service.resolve_budget_amount(user, month_start.year, month_start.month)
        timeline = await self._home_timeline(user.id, from_date, to_date, group_by)
        return HomeReport(
            period=PeriodWindow(from_date=from_date, to_date=to_date),
            currency=user.clinic.currency,
            total_expenses=spent,
            expense_count=len(expense_lines),
            expenses_by_category=[
                NamedAmount(id=str(row[0]), name=row[1], amount=parse_money(row[2])) for row in category_rows
            ],
            expense_lines=[_line(row) for row in expense_lines],
            budget=budget,
            remaining=parse_money(budget - spent),
            percentage_used=percentage_used(spent, budget),
            budget_source=source,
            timeline=timeline,
        )

    async def construction_report(
        self,
        user: User,
        *,
        from_date: date,
        to_date: date,
        group_by: str,
    ) -> ConstructionReport:
        validate_inclusive_range(from_date, to_date)
        spent = await self.totals.construction_expense_total(user.id, from_date, to_date)
        purchase_count = await self.totals.construction_purchase_count(user.id, from_date, to_date)
        category_rows = await self.totals.construction_expenses_by_category(user.id, from_date, to_date)
        material_rows = await self.totals.construction_spending_by_material(user.id, from_date, to_date)
        supplier_rows = await self.totals.construction_expenses_by_supplier(user.id, from_date, to_date)
        purchase_rows = await self.totals.construction_purchase_lines(user.id, from_date, to_date)
        categories = [
            NamedAmount(id=str(row[0]), name=row[1], amount=parse_money(row[2])) for row in category_rows
        ]
        materials = [
            QuantityAmount(
                name=row[1],
                unit=row[2],
                quantity=parse_quantity(row[3]),
                amount=parse_money(row[4]),
            )
            for row in material_rows
        ]
        return ConstructionReport(
            period=PeriodWindow(from_date=from_date, to_date=to_date),
            currency=user.clinic.currency,
            total_expenses=spent,
            purchase_count=purchase_count,
            expenses_by_category=categories,
            spending_by_material=materials,
            expenses_by_supplier=[
                NamedAmount(name=str(row[0]), amount=parse_money(row[1])) for row in supplier_rows
            ],
            top_materials=[NamedAmount(name=item.name, amount=item.amount) for item in materials[:5]],
            top_categories=categories[:5],
            purchases=[
                ConstructionPurchaseLine(
                    purchase_date=row[0],
                    material_name=row[1],
                    category_name=row[2],
                    quantity=parse_quantity(row[3]),
                    unit=row[4],
                    unit_price=parse_money(row[5]),
                    amount=parse_money(row[6]),
                    supplier=row[7],
                )
                for row in purchase_rows
            ],
            timeline=await self._construction_timeline(user.id, from_date, to_date, group_by),
        )

    async def export_clinic(self, user: User, *, from_date: date, to_date: date, group_by: str, fmt: str):
        report = await self.clinic_report(user, from_date=from_date, to_date=to_date, group_by=group_by)
        filename = _export_filename(user.clinic.name, from_date, to_date, fmt)
        if fmt == "pdf":
            return render_clinic_pdf(report, clinic_name=user.clinic.name), filename, "application/pdf"
        return render_clinic_xlsx(report, clinic_name=user.clinic.name), filename, (
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

    async def export_home(self, user: User, *, from_date: date, to_date: date, group_by: str, fmt: str):
        report = await self.home_report(user, from_date=from_date, to_date=to_date, group_by=group_by)
        filename = _export_filename(user.clinic.name, from_date, to_date, fmt, kind="home")
        if fmt == "pdf":
            return render_home_pdf(report, clinic_name=user.clinic.name), filename, "application/pdf"
        return render_home_xlsx(report, clinic_name=user.clinic.name), filename, (
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

    async def export_construction(self, user: User, *, from_date: date, to_date: date, group_by: str, fmt: str):
        report = await self.construction_report(user, from_date=from_date, to_date=to_date, group_by=group_by)
        filename = _export_filename(user.clinic.name, from_date, to_date, fmt, kind="construction")
        if fmt == "pdf":
            return render_construction_pdf(report, clinic_name=user.clinic.name), filename, "application/pdf"
        return render_construction_xlsx(report, clinic_name=user.clinic.name), filename, (
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )

    async def _clinic_timeline(
        self, clinic_id, from_date: date, to_date: date, group_by: str
    ) -> list[TimelinePoint]:
        income_bucket = _date_bucket(TreatmentTransaction.transaction_date, group_by)
        expense_bucket = _date_bucket(ClinicExpense.expense_date, group_by)
        income_stmt = (
            select(income_bucket.label("bucket"), func.coalesce(func.sum(TreatmentTransaction.amount), 0))
            .where(
                TreatmentTransaction.clinic_id == clinic_id,
                TreatmentTransaction.deleted_at.is_(None),
                TreatmentTransaction.transaction_date >= from_date,
                TreatmentTransaction.transaction_date <= to_date,
            )
            .group_by(income_bucket)
        )
        expense_stmt = (
            select(expense_bucket.label("bucket"), func.coalesce(func.sum(ClinicExpense.amount), 0))
            .where(
                ClinicExpense.clinic_id == clinic_id,
                ClinicExpense.deleted_at.is_(None),
                ClinicExpense.expense_date >= from_date,
                ClinicExpense.expense_date <= to_date,
            )
            .group_by(expense_bucket)
        )
        income_map = {row[0]: parse_money(row[1]) for row in (await self.session.execute(income_stmt)).all()}
        expense_map = {row[0]: parse_money(row[1]) for row in (await self.session.execute(expense_stmt)).all()}
        keys = sorted(set(income_map) | set(expense_map))
        points: list[TimelinePoint] = []
        for key in keys:
            income = income_map.get(key, Decimal("0.00"))
            expenses = expense_map.get(key, Decimal("0.00"))
            points.append(
                TimelinePoint(
                    period=str(key),
                    income=income,
                    expenses=expenses,
                    profit=parse_money(income - expenses),
                )
            )
        return points

    async def _home_timeline(self, user_id, from_date: date, to_date: date, group_by: str) -> list[TimelinePoint]:
        bucket = _date_bucket(HomeExpense.expense_date, group_by)
        stmt = (
            select(bucket.label("bucket"), func.coalesce(func.sum(HomeExpense.amount), 0))
            .where(
                HomeExpense.user_id == user_id,
                HomeExpense.deleted_at.is_(None),
                HomeExpense.expense_date >= from_date,
                HomeExpense.expense_date <= to_date,
            )
            .group_by(bucket)
            .order_by(bucket)
        )
        rows = (await self.session.execute(stmt)).all()
        return [
            TimelinePoint(period=str(row[0]), expenses=parse_money(row[1]), income=None, profit=None) for row in rows
        ]

    async def _construction_timeline(
        self, user_id, from_date: date, to_date: date, group_by: str
    ) -> list[TimelinePoint]:
        bucket = _date_bucket(ConstructionPurchase.purchase_date, group_by)
        stmt = (
            select(bucket.label("bucket"), func.coalesce(func.sum(ConstructionPurchase.amount), 0))
            .where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
            .group_by(bucket)
            .order_by(bucket)
        )
        rows = (await self.session.execute(stmt)).all()
        return [
            TimelinePoint(period=str(row[0]), expenses=parse_money(row[1]), income=None, profit=None) for row in rows
        ]


def _line(row) -> ReportLine:
    return ReportLine(entry_date=row[0], name=row[1], detail=row[2], amount=parse_money(row[3]))


def _export_filename(clinic_name: str, from_date: date, to_date: date, fmt: str, kind: str = "clinic") -> str:
    base = safe_filename(f"{clinic_name}_{kind}_report_{from_date}_{to_date}")
    return f"{base}.{fmt}"
