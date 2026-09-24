from datetime import date
from uuid import UUID

from sqlalchemy import func, or_, select

from app.models import HomeBudget, HomeExpense, HomeExpenseCategory
from app.repositories.base import BaseRepository, apply_sort


class HomeExpenseCategoryRepository(BaseRepository):
    def _base(self, user_id: UUID, *, include_deleted: bool = False):
        stmt = select(HomeExpenseCategory).where(HomeExpenseCategory.user_id == user_id)
        if not include_deleted:
            stmt = stmt.where(HomeExpenseCategory.deleted_at.is_(None))
        return stmt

    async def get(self, user_id: UUID, category_id: UUID) -> HomeExpenseCategory | None:
        return await self.session.scalar(self._base(user_id).where(HomeExpenseCategory.id == category_id))

    async def list_filtered(
        self,
        user_id: UUID,
        *,
        search: str | None,
        active: bool | None,
        include_deleted: bool,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[HomeExpenseCategory], int]:
        stmt = self._base(user_id, include_deleted=include_deleted)
        if search:
            stmt = stmt.where(HomeExpenseCategory.name.ilike(f"%{search}%"))
        if active is not None:
            stmt = stmt.where(HomeExpenseCategory.is_active.is_(active))
        stmt = apply_sort(
            stmt,
            HomeExpenseCategory,
            sort,
            "display_order",
            {"display_order", "name", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total

    async def name_taken(self, user_id: UUID, name: str, *, exclude_id: UUID | None = None) -> bool:
        stmt = select(HomeExpenseCategory.id).where(
            HomeExpenseCategory.user_id == user_id,
            HomeExpenseCategory.deleted_at.is_(None),
            func.lower(HomeExpenseCategory.name) == name.lower(),
        )
        if exclude_id:
            stmt = stmt.where(HomeExpenseCategory.id != exclude_id)
        return await self.session.scalar(stmt) is not None

    async def next_order(self, user_id: UUID) -> int:
        return await self.max_order(
            HomeExpenseCategory.display_order,
            HomeExpenseCategory.user_id == user_id,
            HomeExpenseCategory.deleted_at.is_(None),
        )

    async def has_expenses(self, category_id: UUID) -> bool:
        return (
            await self.session.scalar(
                select(HomeExpense.id).where(HomeExpense.category_id == category_id).limit(1)
            )
            is not None
        )


class HomeExpenseRepository(BaseRepository):
    def _base(self, user_id: UUID, *, include_deleted: bool = False):
        stmt = select(HomeExpense).where(HomeExpense.user_id == user_id)
        if not include_deleted:
            stmt = stmt.where(HomeExpense.deleted_at.is_(None))
        return stmt

    async def get(self, user_id: UUID, expense_id: UUID) -> HomeExpense | None:
        return await self.session.scalar(self._base(user_id, include_deleted=True).where(HomeExpense.id == expense_id))

    async def list_filtered(
        self,
        user_id: UUID,
        *,
        from_date: date | None,
        to_date: date | None,
        category_id: UUID | None,
        search: str | None,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[HomeExpense], int]:
        stmt = self._base(user_id)
        if from_date:
            stmt = stmt.where(HomeExpense.expense_date >= from_date)
        if to_date:
            stmt = stmt.where(HomeExpense.expense_date <= to_date)
        if category_id:
            stmt = stmt.where(HomeExpense.category_id == category_id)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.join(HomeExpenseCategory, HomeExpenseCategory.id == HomeExpense.category_id).where(
                or_(HomeExpense.notes.ilike(pattern), HomeExpenseCategory.name.ilike(pattern))
            )
        stmt = apply_sort(stmt, HomeExpense, sort, "-expense_date", {"expense_date", "amount", "created_at"})
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total


class HomeBudgetRepository(BaseRepository):
    async def get(self, user_id: UUID, budget_id: UUID) -> HomeBudget | None:
        return await self.session.scalar(
            select(HomeBudget).where(HomeBudget.user_id == user_id, HomeBudget.id == budget_id)
        )

    async def get_override(self, user_id: UUID, year: int, month: int) -> HomeBudget | None:
        return await self.session.scalar(
            select(HomeBudget).where(
                HomeBudget.user_id == user_id,
                HomeBudget.year == year,
                HomeBudget.month == month,
                HomeBudget.deleted_at.is_(None),
            )
        )

    async def list_filtered(
        self,
        user_id: UUID,
        *,
        page: int,
        page_size: int,
    ) -> tuple[list[HomeBudget], int]:
        stmt = (
            select(HomeBudget)
            .where(HomeBudget.user_id == user_id, HomeBudget.deleted_at.is_(None))
            .order_by(HomeBudget.year.desc(), HomeBudget.month.desc())
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total
