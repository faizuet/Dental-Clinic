from datetime import date
from uuid import UUID

from sqlalchemy import or_, select

from app.models import LabCharge, Patient
from app.repositories.base import BaseRepository, apply_sort


class LabChargeRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(LabCharge).where(LabCharge.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(LabCharge.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, charge_id: UUID) -> LabCharge | None:
        return await self.session.scalar(self._base(clinic_id, include_deleted=True).where(LabCharge.id == charge_id))

    async def list_filtered(
        self,
        clinic_id: UUID,
        *,
        from_date: date | None,
        to_date: date | None,
        patient_id: UUID | None,
        transaction_id: UUID | None,
        search: str | None,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[LabCharge], int]:
        stmt = self._base(clinic_id)
        if from_date:
            stmt = stmt.where(LabCharge.charge_date >= from_date)
        if to_date:
            stmt = stmt.where(LabCharge.charge_date <= to_date)
        if patient_id:
            stmt = stmt.where(LabCharge.patient_id == patient_id)
        if transaction_id:
            stmt = stmt.where(LabCharge.transaction_id == transaction_id)
        if search and search.strip():
            pattern = f"%{search.strip()}%"
            stmt = stmt.outerjoin(Patient, Patient.id == LabCharge.patient_id).where(
                or_(
                    LabCharge.lab_name.ilike(pattern),
                    LabCharge.notes.ilike(pattern),
                    Patient.name.ilike(pattern),
                )
            )
        stmt = apply_sort(
            stmt,
            LabCharge,
            sort,
            "-charge_date",
            {"charge_date", "amount", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total
