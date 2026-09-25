import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import ErrorCode
from app.core.exceptions import ConflictError, ValidationAppError
from app.models import ClinicExpense, ClinicExpenseCategory, User
from app.repositories.base import ensure_version, require_record
from app.repositories.clinic_expenses import ClinicExpenseCategoryRepository, ClinicExpenseRepository
from app.schemas.clinic_expense import ClinicExpenseCreate, ClinicExpenseUpdate
from app.schemas.clinic_expense_category import ClinicExpenseCategoryCreate, ClinicExpenseCategoryUpdate
from app.utils.dates import validate_business_date


class ClinicExpenseService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.categories = ClinicExpenseCategoryRepository(session)
        self.expenses = ClinicExpenseRepository(session)

    async def list_categories(self, user: User, **filters):
        return await self.categories.list_filtered(user.clinic_id, **filters)

    async def get_category(self, user: User, category_id: uuid.UUID) -> ClinicExpenseCategory:
        return require_record(
            await self.categories.get(user.clinic_id, category_id),
            "This clinic expense category is not available on the server. Sync the app and select it again.",
        )

    async def create_category(self, user: User, payload: ClinicExpenseCategoryCreate) -> ClinicExpenseCategory:
        if await self.categories.name_taken(user.clinic_id, payload.name):
            raise ConflictError("A clinic expense category with this name already exists.")
        record = ClinicExpenseCategory(
            id=payload.id or uuid.uuid4(),
            clinic_id=user.clinic_id,
            name=payload.name,
            display_order=payload.display_order
            if payload.display_order is not None
            else await self.categories.next_order(user.clinic_id),
            is_active=payload.is_active,
        )
        return await self.categories.add(record)

    async def update_category(
        self, user: User, category_id: uuid.UUID, payload: ClinicExpenseCategoryUpdate
    ) -> ClinicExpenseCategory:
        record = await self.get_category(user, category_id)
        ensure_version(record, payload.version)
        if payload.name and await self.categories.name_taken(user.clinic_id, payload.name, exclude_id=record.id):
            raise ConflictError("A clinic expense category with this name already exists.")
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
        return await self.expenses.list_filtered(user.clinic_id, **filters)

    async def get_expense(self, user: User, expense_id: uuid.UUID) -> ClinicExpense:
        return require_record(await self.expenses.get(user.clinic_id, expense_id))

    async def create_expense(self, user: User, payload: ClinicExpenseCreate) -> ClinicExpense:
        return await self._build_expense(user, payload)

    async def create_expenses_batch(self, user: User, items: list[ClinicExpenseCreate]) -> list[ClinicExpense]:
        return [await self._build_expense(user, item) for item in items]

    async def update_expense(self, user: User, expense_id: uuid.UUID, payload: ClinicExpenseUpdate) -> ClinicExpense:
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

    async def _build_expense(self, user: User, payload: ClinicExpenseCreate) -> ClinicExpense:
        await self._require_active_category(user, payload.category_id)
        validate_business_date(payload.expense_date, user.clinic.timezone)
        record_id = payload.id or uuid.uuid4()
        existing = await self.expenses.get(user.clinic_id, record_id)
        if existing is not None:
            raise ConflictError("A clinic expense with this id already exists.")
        record = ClinicExpense(
            id=record_id,
            clinic_id=user.clinic_id,
            category_id=payload.category_id,
            created_by=user.id,
            expense_date=payload.expense_date,
            amount=payload.amount,
            notes=payload.notes,
        )
        return await self.expenses.add(record)

    async def _require_active_category(self, user: User, category_id: uuid.UUID) -> ClinicExpenseCategory:
        category = await self.get_category(user, category_id)
        if not category.is_active:
            raise ValidationAppError(
                "Inactive categories cannot be used for new entries.",
                details=[{"field": "category_id", "message": "Select an active category."}],
            )
        return category
