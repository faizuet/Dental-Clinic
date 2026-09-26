import uuid
from decimal import Decimal

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import ErrorCode
from app.core.exceptions import ConflictError, ValidationAppError
from app.models import HomeBudget, HomeExpense, HomeExpenseCategory, User
from app.repositories.base import ensure_version, require_record
from app.repositories.home_expenses import HomeBudgetRepository, HomeExpenseCategoryRepository, HomeExpenseRepository
from app.schemas.home_budget import HomeBudgetCreate, HomeBudgetCurrent, HomeBudgetRead, HomeBudgetUpdate
from app.schemas.home_expense import HomeExpenseCreate, HomeExpenseUpdate
from app.schemas.home_expense_category import HomeExpenseCategoryCreate, HomeExpenseCategoryUpdate
from app.utils.dates import validate_business_date
from app.utils.money import parse_money


class HomeExpenseService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.categories = HomeExpenseCategoryRepository(session)
        self.expenses = HomeExpenseRepository(session)
        self.budgets = HomeBudgetRepository(session)

    async def list_categories(self, user: User, **filters):
        return await self.categories.list_filtered(user.id, **filters)

    async def get_category(self, user: User, category_id: uuid.UUID) -> HomeExpenseCategory:
        return require_record(
            await self.categories.get(user.id, category_id),
            "This home expense category is not available on the server. Sync the app and select it again.",
        )

    async def create_category(self, user: User, payload: HomeExpenseCategoryCreate) -> HomeExpenseCategory:
        if await self.categories.name_taken(user.id, payload.name):
            raise ConflictError("A home expense category with this name already exists.")
        record = HomeExpenseCategory(
            id=payload.id or uuid.uuid4(),
            user_id=user.id,
            name=payload.name,
            display_order=payload.display_order
            if payload.display_order is not None
            else await self.categories.next_order(user.id),
            is_active=payload.is_active,
        )
        return await self.categories.add(record)

    async def update_category(
        self, user: User, category_id: uuid.UUID, payload: HomeExpenseCategoryUpdate
    ) -> HomeExpenseCategory:
        record = await self.get_category(user, category_id)
        ensure_version(record, payload.version)
        if payload.name and await self.categories.name_taken(user.id, payload.name, exclude_id=record.id):
            raise ConflictError("A home expense category with this name already exists.")
        data = payload.model_dump(exclude_unset=True, exclude={"version"})
        for key, value in data.items():
            setattr(record, key, value)
        record.bump()
        await self.session.flush()
        return record

    async def delete_category(self, user: User, category_id: uuid.UUID, version: int) -> None:
        record = await self.get_category(user, category_id)
        ensure_version(record, version)
        if await self.categories.has_expenses(category_id):
            raise ConflictError(
                "This category has expense history and cannot be deleted. Deactivate it instead.",
                code=ErrorCode.CATALOG_IN_USE,
            )
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_expenses(self, user: User, **filters):
        return await self.expenses.list_filtered(user.id, **filters)

    async def get_expense(self, user: User, expense_id: uuid.UUID) -> HomeExpense:
        return require_record(await self.expenses.get(user.id, expense_id))

    async def create_expense(self, user: User, payload: HomeExpenseCreate) -> HomeExpense:
        return await self._build_expense(user, payload)

    async def create_expenses_batch(self, user: User, items: list[HomeExpenseCreate]) -> list[HomeExpense]:
        return [await self._build_expense(user, item) for item in items]

    async def update_expense(self, user: User, expense_id: uuid.UUID, payload: HomeExpenseUpdate) -> HomeExpense:
        record = await self.get_expense(user, expense_id)
        ensure_version(record, payload.version)
        if payload.category_id:
            await self._require_active_category(user, payload.category_id)
        if payload.expense_date:
            validate_business_date(payload.expense_date, user.clinic.timezone)
        data = payload.model_dump(exclude_unset=True, exclude={"version"})
        for key, value in data.items():
            setattr(record, key, value)
        record.bump()
        await self.session.flush()
        return record

    async def delete_expense(self, user: User, expense_id: uuid.UUID, version: int) -> None:
        record = await self.get_expense(user, expense_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_budgets(self, user: User, **filters):
        return await self.budgets.list_filtered(user.id, **filters)

    async def get_budget(self, user: User, budget_id: uuid.UUID) -> HomeBudget:
        record = await self.budgets.get(user.id, budget_id)
        return require_record(record, "This monthly budget was not found. Set the budget again.")

    async def create_budget(self, user: User, payload: HomeBudgetCreate) -> HomeBudget:
        existing = await self.budgets.get_override(user.id, payload.year, payload.month)
        if existing:
            raise ConflictError("A budget override already exists for this month.")
        record_id = payload.id or uuid.uuid4()
        record = HomeBudget(
            id=record_id,
            user_id=user.id,
            year=payload.year,
            month=payload.month,
            amount=payload.amount,
        )
        return await self.budgets.add(record)

    async def upsert_month_budget(self, user: User, payload: HomeBudgetCreate) -> HomeBudget:
        existing = await self.budgets.get_override(user.id, payload.year, payload.month)
        if existing is None:
            return await self.create_budget(user, payload)
        existing.amount = payload.amount
        existing.bump()
        await self.session.flush()
        return existing

    async def update_budget(self, user: User, budget_id: uuid.UUID, payload: HomeBudgetUpdate) -> HomeBudget:
        record = await self.get_budget(user, budget_id)
        ensure_version(record, payload.version)
        if payload.amount is not None:
            record.amount = payload.amount
        record.bump()
        await self.session.flush()
        return record

    async def delete_budget(self, user: User, budget_id: uuid.UUID, version: int) -> None:
        record = await self.get_budget(user, budget_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def current_budget(self, user: User, year: int, month: int) -> HomeBudgetCurrent:
        override = await self.budgets.get_override(user.id, year, month)
        if override:
            return HomeBudgetCurrent(
                year=year,
                month=month,
                amount=parse_money(override.amount),
                source="override",
                override=HomeBudgetRead.model_validate(override),
            )
        return HomeBudgetCurrent(
            year=year,
            month=month,
            amount=parse_money(user.default_home_budget),
            source="default",
            override=None,
        )

    async def resolve_budget_amount(self, user: User, year: int, month: int) -> tuple[Decimal, str]:
        current = await self.current_budget(user, year, month)
        return current.amount, current.source

    async def _build_expense(self, user: User, payload: HomeExpenseCreate) -> HomeExpense:
        await self._require_active_category(user, payload.category_id)
        validate_business_date(payload.expense_date, user.clinic.timezone)
        record_id = payload.id or uuid.uuid4()
        existing = await self.expenses.get(user.id, record_id)
        if existing is not None:
            raise ConflictError("A home expense with this id already exists.")
        record = HomeExpense(
            id=record_id,
            user_id=user.id,
            category_id=payload.category_id,
            expense_date=payload.expense_date,
            amount=payload.amount,
            notes=payload.notes,
        )
        return await self.expenses.add(record)

    async def _require_active_category(self, user: User, category_id: uuid.UUID) -> HomeExpenseCategory:
        category = await self.get_category(user, category_id)
        if not category.is_active:
            raise ValidationAppError(
                "Inactive categories cannot be used for new entries.",
                details=[{"field": "category_id", "message": "Select an active category."}],
            )
        return category
