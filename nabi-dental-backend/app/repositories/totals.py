from collections.abc import Sequence
from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Select, cast, func, select
from sqlalchemy.sql import ColumnElement
from sqlalchemy.types import Date

from app.models import ClinicExpense, ClinicExpenseCategory, HomeExpense, HomeExpenseCategory, Treatment, TreatmentTransaction
from app.repositories.base import BaseRepository
from app.utils.money import parse_money


class TotalsRepository(BaseRepository):
    async def treatment_income_total(self, clinic_id: UUID, from_date: date, to_date: date) -> Decimal:
        value = await self.session.scalar(
            select(func.coalesce(func.sum(TreatmentTransaction.amount), 0)).where(
                TreatmentTransaction.clinic_id == clinic_id,
                TreatmentTransaction.deleted_at.is_(None),
                TreatmentTransaction.transaction_date >= from_date,
                TreatmentTransaction.transaction_date <= to_date,
            )
        )
        return parse_money(value)

    async def clinic_expense_total(self, clinic_id: UUID, from_date: date, to_date: date) -> Decimal:
        value = await self.session.scalar(
            select(func.coalesce(func.sum(ClinicExpense.amount), 0)).where(
                ClinicExpense.clinic_id == clinic_id,
                ClinicExpense.deleted_at.is_(None),
                ClinicExpense.expense_date >= from_date,
                ClinicExpense.expense_date <= to_date,
            )
        )
        return parse_money(value)

    async def home_expense_total(self, user_id: UUID, from_date: date, to_date: date) -> Decimal:
        value = await self.session.scalar(
            select(func.coalesce(func.sum(HomeExpense.amount), 0)).where(
                HomeExpense.user_id == user_id,
                HomeExpense.deleted_at.is_(None),
                HomeExpense.expense_date >= from_date,
                HomeExpense.expense_date <= to_date,
            )
        )
        return parse_money(value)

    async def income_by_treatment(self, clinic_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(Treatment.id, Treatment.name, func.coalesce(func.sum(TreatmentTransaction.amount), 0))
            .join(Treatment, Treatment.id == TreatmentTransaction.treatment_id)
            .where(
                TreatmentTransaction.clinic_id == clinic_id,
                TreatmentTransaction.deleted_at.is_(None),
                TreatmentTransaction.transaction_date >= from_date,
                TreatmentTransaction.transaction_date <= to_date,
            )
            .group_by(Treatment.id, Treatment.name)
            .order_by(func.sum(TreatmentTransaction.amount).desc())
        )
        return (await self.session.execute(stmt)).all()

    async def clinic_expenses_by_category(self, clinic_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(
                ClinicExpenseCategory.id,
                ClinicExpenseCategory.name,
                func.coalesce(func.sum(ClinicExpense.amount), 0),
            )
            .join(ClinicExpenseCategory, ClinicExpenseCategory.id == ClinicExpense.category_id)
            .where(
                ClinicExpense.clinic_id == clinic_id,
                ClinicExpense.deleted_at.is_(None),
                ClinicExpense.expense_date >= from_date,
                ClinicExpense.expense_date <= to_date,
            )
            .group_by(ClinicExpenseCategory.id, ClinicExpenseCategory.name)
            .order_by(func.sum(ClinicExpense.amount).desc())
        )
        return (await self.session.execute(stmt)).all()

    async def home_expenses_by_category(self, user_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(
                HomeExpenseCategory.id,
                HomeExpenseCategory.name,
                func.coalesce(func.sum(HomeExpense.amount), 0),
            )
            .join(HomeExpenseCategory, HomeExpenseCategory.id == HomeExpense.category_id)
            .where(
                HomeExpense.user_id == user_id,
                HomeExpense.deleted_at.is_(None),
                HomeExpense.expense_date >= from_date,
                HomeExpense.expense_date <= to_date,
            )
            .group_by(HomeExpenseCategory.id, HomeExpenseCategory.name)
            .order_by(func.sum(HomeExpense.amount).desc())
        )
        return (await self.session.execute(stmt)).all()

    async def grouped_sums(
        self,
        stmt: Select,
        date_column: ColumnElement,
        group_by: str,
    ) -> Sequence[tuple]:
        bucket = _date_bucket(date_column, group_by)
        grouped = stmt.add_columns(bucket.label("bucket")).group_by(bucket).order_by(bucket)
        return (await self.session.execute(grouped)).all()


def _date_bucket(column: ColumnElement, group_by: str):
    mapping = {
        "day": column,
        "week": cast(func.date_trunc("week", column), Date),
        "month": cast(func.date_trunc("month", column), Date),
        "year": cast(func.date_trunc("year", column), Date),
    }
    return mapping.get(group_by, column)
