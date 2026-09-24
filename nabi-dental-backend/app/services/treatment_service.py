import uuid
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import ErrorCode
from app.core.exceptions import ConflictError, NotFoundError, ValidationAppError
from app.models import Treatment, TreatmentCategory, TreatmentTransaction, User
from app.repositories.base import ensure_version, require_record
from app.repositories.treatments import TreatmentCategoryRepository, TreatmentRepository, TreatmentTransactionRepository
from app.schemas.treatment import TreatmentCreate, TreatmentUpdate
from app.schemas.treatment_category import TreatmentCategoryCreate, TreatmentCategoryUpdate
from app.schemas.treatment_transaction import TreatmentTransactionCreate, TreatmentTransactionUpdate
from app.utils.dates import validate_business_date


class TreatmentService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.categories = TreatmentCategoryRepository(session)
        self.treatments = TreatmentRepository(session)
        self.transactions = TreatmentTransactionRepository(session)

    async def list_categories(self, user: User, **filters):
        return await self.categories.list_filtered(user.clinic_id, **filters)

    async def get_category(self, user: User, category_id: uuid.UUID) -> TreatmentCategory:
        return require_record(await self.categories.get(user.clinic_id, category_id))

    async def create_category(self, user: User, payload: TreatmentCategoryCreate) -> TreatmentCategory:
        if await self.categories.name_taken(user.clinic_id, payload.name):
            raise ConflictError("A treatment category with this name already exists.")
        record = TreatmentCategory(
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
        self, user: User, category_id: uuid.UUID, payload: TreatmentCategoryUpdate
    ) -> TreatmentCategory:
        record = await self.get_category(user, category_id)
        ensure_version(record, payload.version)
        if payload.name and await self.categories.name_taken(user.clinic_id, payload.name, exclude_id=record.id):
            raise ConflictError("A treatment category with this name already exists.")
        _apply_updates(record, payload, {"version"})
        record.bump()
        await self.session.flush()
        return record

    async def delete_category(self, user: User, category_id: uuid.UUID, version: int) -> None:
        record = await self.get_category(user, category_id)
        ensure_version(record, version)
        if await self.categories.has_treatments(category_id):
            raise ConflictError(
                "This category has treatments and cannot be deleted. Deactivate it instead.",
                code=ErrorCode.CATALOG_IN_USE,
            )
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_treatments(self, user: User, **filters):
        return await self.treatments.list_filtered(user.clinic_id, **filters)

    async def get_treatment(self, user: User, treatment_id: uuid.UUID) -> Treatment:
        return require_record(await self.treatments.get(user.clinic_id, treatment_id))

    async def create_treatment(self, user: User, payload: TreatmentCreate) -> Treatment:
        category = await self.get_category(user, payload.category_id)
        if await self.treatments.name_taken(user.clinic_id, payload.name):
            raise ConflictError("A treatment with this name already exists.")
        record = Treatment(
            id=payload.id or uuid.uuid4(),
            clinic_id=user.clinic_id,
            category_id=category.id,
            name=payload.name,
            default_price=payload.default_price,
            display_order=payload.display_order
            if payload.display_order is not None
            else await self.treatments.next_order(user.clinic_id, category.id),
            is_active=payload.is_active,
        )
        return await self.treatments.add(record)

    async def update_treatment(self, user: User, treatment_id: uuid.UUID, payload: TreatmentUpdate) -> Treatment:
        record = await self.get_treatment(user, treatment_id)
        ensure_version(record, payload.version)
        if payload.category_id:
            await self.get_category(user, payload.category_id)
        if payload.name and await self.treatments.name_taken(user.clinic_id, payload.name, exclude_id=record.id):
            raise ConflictError("A treatment with this name already exists.")
        _apply_updates(record, payload, {"version"})
        record.bump()
        await self.session.flush()
        return record

    async def delete_treatment(self, user: User, treatment_id: uuid.UUID, version: int) -> None:
        record = await self.get_treatment(user, treatment_id)
        ensure_version(record, version)
        if await self.treatments.has_transactions(treatment_id):
            raise ConflictError(
                "This treatment has transaction history and cannot be deleted. Deactivate it instead.",
                code=ErrorCode.CATALOG_IN_USE,
            )
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_transactions(self, user: User, **filters):
        return await self.transactions.list_filtered(user.clinic_id, **filters)

    async def get_transaction(self, user: User, transaction_id: uuid.UUID) -> TreatmentTransaction:
        record = await self.transactions.get(user.clinic_id, transaction_id)
        return require_record(record)

    async def create_transaction(self, user: User, payload: TreatmentTransactionCreate) -> TreatmentTransaction:
        return await self._build_transaction(user, payload)

    async def create_transactions_batch(
        self, user: User, items: list[TreatmentTransactionCreate]
    ) -> list[TreatmentTransaction]:
        return [await self._build_transaction(user, item, flush=False) for item in items]

    async def update_transaction(
        self, user: User, transaction_id: uuid.UUID, payload: TreatmentTransactionUpdate
    ) -> TreatmentTransaction:
        record = await self.get_transaction(user, transaction_id)
        ensure_version(record, payload.version)
        if payload.treatment_id:
            await self._require_active_treatment(user, payload.treatment_id)
        if payload.transaction_date:
            validate_business_date(payload.transaction_date, user.clinic.timezone)
        _apply_updates(record, payload, {"version"})
        record.bump()
        await self.session.flush()
        return record

    async def delete_transaction(self, user: User, transaction_id: uuid.UUID, version: int) -> None:
        record = await self.get_transaction(user, transaction_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def _build_transaction(
        self, user: User, payload: TreatmentTransactionCreate, *, flush: bool = True
    ) -> TreatmentTransaction:
        await self._require_active_treatment(user, payload.treatment_id)
        validate_business_date(payload.transaction_date, user.clinic.timezone)
        record_id = payload.id or uuid.uuid4()
        existing = await self.transactions.get(user.clinic_id, record_id)
        if existing is not None:
            raise ConflictError("A treatment transaction with this id already exists.")
        record = TreatmentTransaction(
            id=record_id,
            clinic_id=user.clinic_id,
            treatment_id=payload.treatment_id,
            created_by=user.id,
            transaction_date=payload.transaction_date,
            quantity=payload.quantity,
            amount=payload.amount,
            notes=payload.notes,
        )
        self.session.add(record)
        if flush:
            await self.session.flush()
            await self.session.refresh(record)
        else:
            await self.session.flush()
        return record

    async def _require_active_treatment(self, user: User, treatment_id: uuid.UUID) -> Treatment:
        treatment = await self.get_treatment(user, treatment_id)
        if not treatment.is_active:
            raise ValidationAppError(
                "Inactive treatments cannot be used for new entries.",
                details=[{"field": "treatment_id", "message": "Select an active treatment."}],
            )
        return treatment


def _apply_updates(record, payload, skip: set[str]) -> None:
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        if key in skip:
            continue
        setattr(record, key, value)
