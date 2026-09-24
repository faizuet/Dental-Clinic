from datetime import date
from uuid import UUID

from sqlalchemy import func, or_, select

from app.models import ClinicExpense, ClinicExpenseCategory
from app.repositories.base import BaseRepository, apply_sort


class ClinicExpenseCategoryRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(ClinicExpenseCategory).where(ClinicExpenseCategory.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(ClinicExpenseCategory.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, category_id: UUID) -> ClinicExpenseCategory | None:
        return await self.session.scalar(self._base(clinic_id).where(ClinicExpenseCategory.id == category_id))

    async def list_filtered(
        self,
        clinic_id: UUID,
        *,
        search: str | None,
        active: bool | None,
        include_deleted: bool,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[ClinicExpenseCategory], int]:
        stmt = self._base(clinic_id, include_deleted=include_deleted)
        if search:
            stmt = stmt.where(ClinicExpenseCategory.name.ilike(f"%{search}%"))
        if active is not None:
            stmt = stmt.where(ClinicExpenseCategory.is_active.is_(active))
        stmt = apply_sort(
            stmt,
            ClinicExpenseCategory,
            sort,
            "display_order",
            {"display_order", "name", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total

    async def name_taken(self, clinic_id: UUID, name: str, *, exclude_id: UUID | None = None) -> bool:
        stmt = select(ClinicExpenseCategory.id).where(
            ClinicExpenseCategory.clinic_id == clinic_id,
            ClinicExpenseCategory.deleted_at.is_(None),
            func.lower(ClinicExpenseCategory.name) == name.lower(),
        )
        if exclude_id:
            stmt = stmt.where(ClinicExpenseCategory.id != exclude_id)
        return await self.session.scalar(stmt) is not None

    async def next_order(self, clinic_id: UUID) -> int:
        return await self.max_order(
            ClinicExpenseCategory.display_order,
            ClinicExpenseCategory.clinic_id == clinic_id,
            ClinicExpenseCategory.deleted_at.is_(None),
        )

    async def has_expenses(self, category_id: UUID) -> bool:
        return (
            await self.session.scalar(
                select(ClinicExpense.id).where(ClinicExpense.category_id == category_id).limit(1)
            )
            is not None
        )


class ClinicExpenseRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(ClinicExpense).where(ClinicExpense.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(ClinicExpense.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, expense_id: UUID) -> ClinicExpense | None:
        return await self.session.scalar(self._base(clinic_id, include_deleted=True).where(ClinicExpense.id == expense_id))

    async def list_filtered(
        self,
        clinic_id: UUID,
        *,
        from_date: date | None,
        to_date: date | None,
        category_id: UUID | None,
        search: str | None,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[ClinicExpense], int]:
        stmt = self._base(clinic_id)
        if from_date:
            stmt = stmt.where(ClinicExpense.expense_date >= from_date)
        if to_date:
            stmt = stmt.where(ClinicExpense.expense_date <= to_date)
        if category_id:
            stmt = stmt.where(ClinicExpense.category_id == category_id)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.join(ClinicExpenseCategory, ClinicExpenseCategory.id == ClinicExpense.category_id).where(
                or_(ClinicExpense.notes.ilike(pattern), ClinicExpenseCategory.name.ilike(pattern))
            )
        stmt = apply_sort(
            stmt,
            ClinicExpense,
            sort,
            "-expense_date",
            {"expense_date", "amount", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total
