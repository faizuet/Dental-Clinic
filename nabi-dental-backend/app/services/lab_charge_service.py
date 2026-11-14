import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError, ValidationAppError
from app.models import LabCharge, User
from app.repositories.base import ensure_version, require_record
from app.repositories.lab_charges import LabChargeRepository
from app.repositories.treatments import PatientRepository, TreatmentTransactionRepository
from app.schemas.lab_charge import LabChargeCreate, LabChargeUpdate
from app.utils.dates import validate_business_date


class LabChargeService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.charges = LabChargeRepository(session)
        self.patients = PatientRepository(session)
        self.transactions = TreatmentTransactionRepository(session)

    async def list_charges(self, user: User, **filters):
        return await self.charges.list_filtered(user.clinic_id, **filters)

    async def get_charge(self, user: User, charge_id: uuid.UUID) -> LabCharge:
        return require_record(await self.charges.get(user.clinic_id, charge_id))

    async def create_charge(self, user: User, payload: LabChargeCreate) -> LabCharge:
        validate_business_date(payload.charge_date, user.clinic.timezone)
        record_id = payload.id or uuid.uuid4()
        if await self.charges.get(user.clinic_id, record_id) is not None:
            raise ConflictError("A lab charge with this id already exists.")
        patient_id, transaction_id = await self._resolve_links(user, payload.patient_id, payload.transaction_id)
        record = LabCharge(
            id=record_id,
            clinic_id=user.clinic_id,
            created_by=user.id,
            patient_id=patient_id,
            transaction_id=transaction_id,
            charge_date=payload.charge_date,
            amount=payload.amount,
            lab_name=payload.lab_name,
            notes=payload.notes,
        )
        return await self.charges.add(record)

    async def update_charge(self, user: User, charge_id: uuid.UUID, payload: LabChargeUpdate) -> LabCharge:
        record = await self.get_charge(user, charge_id)
        ensure_version(record, payload.version)
        data = payload.model_dump(exclude_unset=True, exclude={"version"})
        if data.get("charge_date"):
            validate_business_date(data["charge_date"], user.clinic.timezone)
        if "patient_id" in data or "transaction_id" in data:
            patient_id = data.get("patient_id", record.patient_id)
            transaction_id = data.get("transaction_id", record.transaction_id)
            data["patient_id"], data["transaction_id"] = await self._resolve_links(
                user,
                patient_id,
                transaction_id,
                current_patient_id=record.patient_id,
                current_transaction_id=record.transaction_id,
            )
        for key, value in data.items():
            setattr(record, key, value)
        record.bump()
        await self.session.flush()
        return record

    async def delete_charge(self, user: User, charge_id: uuid.UUID, version: int) -> LabCharge:
        record = await self.get_charge(user, charge_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def _resolve_links(
        self,
        user: User,
        patient_id: uuid.UUID | None,
        transaction_id: uuid.UUID | None,
        *,
        current_patient_id: uuid.UUID | None = None,
        current_transaction_id: uuid.UUID | None = None,
    ) -> tuple[uuid.UUID | None, uuid.UUID | None]:
        # Links that are already stored stay valid even if that patient or visit was deleted later.
        if transaction_id is not None:
            visit = await self.transactions.get(user.clinic_id, transaction_id)
            if visit is None or (visit.deleted_at is not None and transaction_id != current_transaction_id):
                raise ValidationAppError(
                    "This treatment visit is not available. Sync the app and select it again.",
                    details=[{"field": "transaction_id", "message": "Select an existing treatment visit."}],
                )
            if visit.patient_id is not None:
                if patient_id is None:
                    patient_id = visit.patient_id
                elif patient_id != visit.patient_id:
                    raise ValidationAppError(
                        "The selected treatment visit belongs to a different patient.",
                        details=[{"field": "transaction_id", "message": "Select a visit for this patient."}],
                    )
        if patient_id is not None:
            patient = await self.patients.get(user.clinic_id, patient_id)
            if patient is None or (patient.deleted_at is not None and patient_id != current_patient_id):
                raise ValidationAppError(
                    "This patient is not available. Sync the app and select the patient again.",
                    details=[{"field": "patient_id", "message": "Select an existing patient."}],
                )
        return patient_id, transaction_id
