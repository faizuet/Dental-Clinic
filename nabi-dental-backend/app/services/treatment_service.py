import uuid
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import ErrorCode
from app.core.exceptions import ConflictError, NotFoundError, ValidationAppError
from sqlalchemy import inspect as sa_inspect

from app.models import Patient, Treatment, TreatmentCategory, TreatmentTransaction, User
from app.repositories.base import ensure_version, require_record
from app.repositories.treatments import (
    PatientRepository,
    TreatmentAttachmentRepository,
    TreatmentCategoryRepository,
    TreatmentRepository,
    TreatmentTransactionRepository,
)
from app.schemas.patient import PatientCreate, PatientUpdate
from app.schemas.treatment import TreatmentCreate, TreatmentUpdate
from app.schemas.treatment_category import TreatmentCategoryCreate, TreatmentCategoryUpdate
from app.schemas.treatment_transaction import (
    TreatmentAttachmentRead,
    TreatmentTransactionCreate,
    TreatmentTransactionRead,
    TreatmentTransactionUpdate,
)
from app.utils.dates import validate_business_date
from app.utils.treatment_details import clinical_summary


class TreatmentService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.categories = TreatmentCategoryRepository(session)
        self.treatments = TreatmentRepository(session)
        self.transactions = TreatmentTransactionRepository(session)
        self.patients = PatientRepository(session)
        self.attachments = TreatmentAttachmentRepository(session)

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

    async def list_patients(self, user: User, **filters):
        return await self.patients.list_filtered(user.clinic_id, **filters)

    async def get_patient(self, user: User, patient_id: uuid.UUID) -> Patient:
        return require_record(await self.patients.get(user.clinic_id, patient_id))

    async def create_patient(self, user: User, payload: PatientCreate) -> Patient:
        record = Patient(
            id=payload.id or uuid.uuid4(),
            clinic_id=user.clinic_id,
            name=payload.name,
            phone=payload.phone,
            notes=payload.notes,
        )
        return await self.patients.add(record)

    async def update_patient(self, user: User, patient_id: uuid.UUID, payload: PatientUpdate) -> Patient:
        record = await self.get_patient(user, patient_id)
        ensure_version(record, payload.version)
        _apply_updates(record, payload, {"version"})
        record.bump()
        await self.session.flush()
        return record

    async def delete_patient(self, user: User, patient_id: uuid.UUID, version: int) -> None:
        record = await self.get_patient(user, patient_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_transactions(self, user: User, **filters):
        return await self.transactions.list_filtered(user.clinic_id, **filters)

    async def get_transaction(self, user: User, transaction_id: uuid.UUID) -> TreatmentTransaction:
        record = await self.transactions.get_loaded(user.clinic_id, transaction_id)
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
        if payload.patient_id:
            await self.get_patient(user, payload.patient_id)
        _apply_updates(record, payload, {"version"})
        record.bump()
        await self.session.flush()
        loaded = await self.transactions.get_loaded(user.clinic_id, record.id)
        return loaded or record

    async def delete_transaction(self, user: User, transaction_id: uuid.UUID, version: int) -> None:
        record = await self.get_transaction(user, transaction_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def get_attachment(self, user: User, attachment_id: uuid.UUID):
        return require_record(await self.attachments.get(user.clinic_id, attachment_id))

    def serialize_transaction(self, record: TreatmentTransaction) -> TreatmentTransactionRead:
        return serialize_transaction(record)

    async def _build_transaction(
        self, user: User, payload: TreatmentTransactionCreate, *, flush: bool = True
    ) -> TreatmentTransaction:
        await self._require_active_treatment(user, payload.treatment_id)
        validate_business_date(payload.transaction_date, user.clinic.timezone)
        if payload.patient_id:
            await self.get_patient(user, payload.patient_id)
        record_id = payload.id or uuid.uuid4()
        existing = await self.transactions.get(user.clinic_id, record_id)
        if existing is not None:
            raise ConflictError("A treatment transaction with this id already exists.")
        record = TreatmentTransaction(
            id=record_id,
            clinic_id=user.clinic_id,
            treatment_id=payload.treatment_id,
            created_by=user.id,
            patient_id=payload.patient_id,
            serial_no=await self.transactions.next_serial(user.clinic_id),
            transaction_date=payload.transaction_date,
            quantity=payload.quantity,
            amount=payload.amount,
            sub_treatment=payload.sub_treatment,
            details=payload.details or {},
            notes=payload.notes,
        )
        self.session.add(record)
        await self.session.flush()
        loaded = await self.transactions.get_loaded(user.clinic_id, record.id)
        return loaded or record

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


def _rel_loaded(record, name: str) -> bool:
    try:
        return name not in sa_inspect(record).unloaded
    except Exception:
        return False


def serialize_transaction(record: TreatmentTransaction) -> TreatmentTransactionRead:
    patient_name = record.patient.name if _rel_loaded(record, "patient") and record.patient else None
    patient_phone = record.patient.phone if _rel_loaded(record, "patient") and record.patient else None
    treatment_name = record.treatment.name if _rel_loaded(record, "treatment") and record.treatment else None
    category_name = None
    if _rel_loaded(record, "treatment") and record.treatment is not None and _rel_loaded(record.treatment, "category"):
        category_name = record.treatment.category.name if record.treatment.category else None
    attachments = []
    if _rel_loaded(record, "attachments"):
        attachments = [
            TreatmentAttachmentRead.model_validate(item)
            for item in record.attachments
            if item.deleted_at is None
        ]
    details = record.details or {}
    return TreatmentTransactionRead(
        id=record.id,
        created_at=record.created_at,
        updated_at=record.updated_at,
        deleted_at=record.deleted_at,
        version=record.version,
        clinic_id=record.clinic_id,
        treatment_id=record.treatment_id,
        created_by=record.created_by,
        transaction_date=record.transaction_date,
        quantity=record.quantity,
        amount=record.amount,
        notes=record.notes,
        patient_id=record.patient_id,
        serial_no=record.serial_no,
        sub_treatment=record.sub_treatment,
        details=details,
        patient_name=patient_name,
        patient_phone=patient_phone,
        treatment_name=treatment_name,
        category_name=category_name,
        details_text=clinical_summary(details, record.sub_treatment),
        attachments=attachments,
    )
