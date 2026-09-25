from collections.abc import Sequence
from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Select, cast, func, select
from sqlalchemy.sql import ColumnElement
from sqlalchemy.types import Date

from app.models import (
    ClinicExpense,
    ClinicExpenseCategory,
    ConstructionMaterial,
    ConstructionMaterialCategory,
    ConstructionPurchase,
    HomeExpense,
    HomeExpenseCategory,
    Treatment,
    TreatmentTransaction,
)
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

    async def construction_expense_total(self, user_id: UUID, from_date: date, to_date: date) -> Decimal:
        value = await self.session.scalar(
            select(func.coalesce(func.sum(ConstructionPurchase.amount), 0)).where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
        )
        return parse_money(value)

    async def construction_purchase_count(self, user_id: UUID, from_date: date, to_date: date) -> int:
        value = await self.session.scalar(
            select(func.count()).where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
        )
        return int(value or 0)

    async def construction_expenses_by_category(self, user_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(
                ConstructionMaterialCategory.id,
                ConstructionMaterialCategory.name,
                func.coalesce(func.sum(ConstructionPurchase.amount), 0),
            )
            .join(ConstructionMaterial, ConstructionMaterial.id == ConstructionPurchase.material_id)
            .join(
                ConstructionMaterialCategory,
                ConstructionMaterialCategory.id == ConstructionMaterial.category_id,
            )
            .where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
            .group_by(ConstructionMaterialCategory.id, ConstructionMaterialCategory.name)
            .order_by(func.sum(ConstructionPurchase.amount).desc())
        )
        return (await self.session.execute(stmt)).all()

    async def construction_spending_by_material(self, user_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(
                ConstructionMaterial.id,
                ConstructionMaterial.name,
                ConstructionMaterial.unit,
                func.coalesce(func.sum(ConstructionPurchase.quantity), 0),
                func.coalesce(func.sum(ConstructionPurchase.amount), 0),
            )
            .join(ConstructionMaterial, ConstructionMaterial.id == ConstructionPurchase.material_id)
            .where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
            .group_by(ConstructionMaterial.id, ConstructionMaterial.name, ConstructionMaterial.unit)
            .order_by(func.sum(ConstructionPurchase.amount).desc())
        )
        return (await self.session.execute(stmt)).all()

    async def construction_expenses_by_supplier(self, user_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        supplier = func.coalesce(func.nullif(func.trim(ConstructionPurchase.supplier), ""), "Unspecified")
        stmt = (
            select(supplier, func.coalesce(func.sum(ConstructionPurchase.amount), 0))
            .where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
            .group_by(supplier)
            .order_by(func.sum(ConstructionPurchase.amount).desc())
        )
        return (await self.session.execute(stmt)).all()

    async def clinic_income_lines(self, clinic_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(
                TreatmentTransaction.transaction_date,
                Treatment.name,
                TreatmentTransaction.notes,
                TreatmentTransaction.amount,
            )
            .join(Treatment, Treatment.id == TreatmentTransaction.treatment_id)
            .where(
                TreatmentTransaction.clinic_id == clinic_id,
                TreatmentTransaction.deleted_at.is_(None),
                TreatmentTransaction.transaction_date >= from_date,
                TreatmentTransaction.transaction_date <= to_date,
            )
            .order_by(TreatmentTransaction.transaction_date, Treatment.name)
        )
        return (await self.session.execute(stmt)).all()

    async def clinic_expense_lines(self, clinic_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(ClinicExpense.expense_date, ClinicExpenseCategory.name, ClinicExpense.notes, ClinicExpense.amount)
            .join(ClinicExpenseCategory, ClinicExpenseCategory.id == ClinicExpense.category_id)
            .where(
                ClinicExpense.clinic_id == clinic_id,
                ClinicExpense.deleted_at.is_(None),
                ClinicExpense.expense_date >= from_date,
                ClinicExpense.expense_date <= to_date,
            )
            .order_by(ClinicExpense.expense_date, ClinicExpenseCategory.name)
        )
        return (await self.session.execute(stmt)).all()

    async def home_expense_lines(self, user_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(HomeExpense.expense_date, HomeExpenseCategory.name, HomeExpense.notes, HomeExpense.amount)
            .join(HomeExpenseCategory, HomeExpenseCategory.id == HomeExpense.category_id)
            .where(
                HomeExpense.user_id == user_id,
                HomeExpense.deleted_at.is_(None),
                HomeExpense.expense_date >= from_date,
                HomeExpense.expense_date <= to_date,
            )
            .order_by(HomeExpense.expense_date, HomeExpenseCategory.name)
        )
        return (await self.session.execute(stmt)).all()

    async def construction_purchase_lines(self, user_id: UUID, from_date: date, to_date: date) -> Sequence[tuple]:
        stmt = (
            select(
                ConstructionPurchase.purchase_date,
                ConstructionMaterial.name,
                ConstructionMaterialCategory.name,
                ConstructionPurchase.quantity,
                ConstructionPurchase.unit,
                ConstructionPurchase.unit_price,
                ConstructionPurchase.amount,
                ConstructionPurchase.supplier,
            )
            .join(ConstructionMaterial, ConstructionMaterial.id == ConstructionPurchase.material_id)
            .join(
                ConstructionMaterialCategory,
                ConstructionMaterialCategory.id == ConstructionMaterial.category_id,
            )
            .where(
                ConstructionPurchase.user_id == user_id,
                ConstructionPurchase.deleted_at.is_(None),
                ConstructionPurchase.purchase_date >= from_date,
                ConstructionPurchase.purchase_date <= to_date,
            )
            .order_by(ConstructionPurchase.purchase_date, ConstructionMaterial.name)
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
    group_by = str(group_by)
    mapping = {
        "day": column,
        "week": cast(func.date_trunc("week", column), Date),
        "month": cast(func.date_trunc("month", column), Date),
        "year": cast(func.date_trunc("year", column), Date),
    }
    return mapping.get(group_by, column)
