from datetime import date
from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from app.models import Patient, Treatment, TreatmentAttachment, TreatmentCategory, TreatmentTransaction
from app.repositories.base import BaseRepository, apply_sort


class TreatmentCategoryRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(TreatmentCategory).where(TreatmentCategory.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(TreatmentCategory.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, category_id: UUID) -> TreatmentCategory | None:
        return await self.session.scalar(
            self._base(clinic_id).where(TreatmentCategory.id == category_id)
        )

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
    ) -> tuple[list[TreatmentCategory], int]:
        stmt = self._base(clinic_id, include_deleted=include_deleted)
        if search:
            stmt = stmt.where(TreatmentCategory.name.ilike(f"%{search}%"))
        if active is not None:
            stmt = stmt.where(TreatmentCategory.is_active.is_(active))
        stmt = apply_sort(stmt, TreatmentCategory, sort, "display_order", {"display_order", "name", "created_at"})
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total

    async def name_taken(self, clinic_id: UUID, name: str, *, exclude_id: UUID | None = None) -> bool:
        stmt = select(TreatmentCategory.id).where(
            TreatmentCategory.clinic_id == clinic_id,
            TreatmentCategory.deleted_at.is_(None),
            func.lower(TreatmentCategory.name) == name.lower(),
        )
        if exclude_id:
            stmt = stmt.where(TreatmentCategory.id != exclude_id)
        return await self.session.scalar(stmt) is not None

    async def next_order(self, clinic_id: UUID) -> int:
        return await self.max_order(
            TreatmentCategory.display_order,
            TreatmentCategory.clinic_id == clinic_id,
            TreatmentCategory.deleted_at.is_(None),
        )

    async def has_treatments(self, category_id: UUID) -> bool:
        return (
            await self.session.scalar(
                select(Treatment.id).where(
                    Treatment.category_id == category_id,
                    Treatment.deleted_at.is_(None),
                ).limit(1)
            )
            is not None
        )


class TreatmentRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(Treatment).where(Treatment.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(Treatment.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, treatment_id: UUID) -> Treatment | None:
        return await self.session.scalar(self._base(clinic_id).where(Treatment.id == treatment_id))

    async def list_filtered(
        self,
        clinic_id: UUID,
        *,
        search: str | None,
        active: bool | None,
        category_id: UUID | None,
        include_deleted: bool,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[Treatment], int]:
        stmt = self._base(clinic_id, include_deleted=include_deleted)
        if search:
            stmt = stmt.where(Treatment.name.ilike(f"%{search}%"))
        if active is not None:
            stmt = stmt.where(Treatment.is_active.is_(active))
        if category_id:
            stmt = stmt.where(Treatment.category_id == category_id)
        stmt = apply_sort(stmt, Treatment, sort, "display_order", {"display_order", "name", "created_at"})
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total

    async def name_taken(self, clinic_id: UUID, name: str, *, exclude_id: UUID | None = None) -> bool:
        stmt = select(Treatment.id).where(
            Treatment.clinic_id == clinic_id,
            Treatment.deleted_at.is_(None),
            func.lower(Treatment.name) == name.lower(),
        )
        if exclude_id:
            stmt = stmt.where(Treatment.id != exclude_id)
        return await self.session.scalar(stmt) is not None

    async def next_order(self, clinic_id: UUID, category_id: UUID) -> int:
        return await self.max_order(
            Treatment.display_order,
            Treatment.clinic_id == clinic_id,
            Treatment.category_id == category_id,
            Treatment.deleted_at.is_(None),
        )

    async def has_transactions(self, treatment_id: UUID) -> bool:
        return (
            await self.session.scalar(
                select(TreatmentTransaction.id).where(TreatmentTransaction.treatment_id == treatment_id).limit(1)
            )
            is not None
        )


def _visit_options():
    return (
        selectinload(TreatmentTransaction.patient),
        selectinload(TreatmentTransaction.treatment).selectinload(Treatment.category),
        selectinload(TreatmentTransaction.attachments),
    )


class PatientRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(Patient).where(Patient.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(Patient.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, patient_id: UUID) -> Patient | None:
        return await self.session.scalar(self._base(clinic_id, include_deleted=True).where(Patient.id == patient_id))

    async def list_filtered(
        self,
        clinic_id: UUID,
        *,
        search: str | None,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[Patient], int]:
        stmt = self._base(clinic_id)
        if search and search.strip():
            pattern = f"%{search.strip()}%"
            stmt = stmt.where(or_(Patient.name.ilike(pattern), Patient.phone.ilike(pattern)))
        stmt = apply_sort(stmt, Patient, sort, "name", {"name", "created_at", "updated_at"})
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total


class TreatmentAttachmentRepository(BaseRepository):
    async def get(self, clinic_id: UUID, attachment_id: UUID) -> TreatmentAttachment | None:
        return await self.session.scalar(
            select(TreatmentAttachment).where(
                TreatmentAttachment.clinic_id == clinic_id,
                TreatmentAttachment.id == attachment_id,
            )
        )

    async def live_count(self, transaction_id: UUID) -> int:
        return int(
            await self.session.scalar(
                select(func.count())
                .select_from(TreatmentAttachment)
                .where(
                    TreatmentAttachment.transaction_id == transaction_id,
                    TreatmentAttachment.deleted_at.is_(None),
                )
            )
            or 0
        )


class TreatmentTransactionRepository(BaseRepository):
    def _base(self, clinic_id: UUID, *, include_deleted: bool = False):
        stmt = select(TreatmentTransaction).where(TreatmentTransaction.clinic_id == clinic_id)
        if not include_deleted:
            stmt = stmt.where(TreatmentTransaction.deleted_at.is_(None))
        return stmt

    async def get(self, clinic_id: UUID, transaction_id: UUID) -> TreatmentTransaction | None:
        return await self.session.scalar(
            self._base(clinic_id, include_deleted=True).where(TreatmentTransaction.id == transaction_id)
        )

    async def get_loaded(self, clinic_id: UUID, transaction_id: UUID) -> TreatmentTransaction | None:
        return await self.session.scalar(
            self._base(clinic_id, include_deleted=True)
            .options(*_visit_options())
            .where(TreatmentTransaction.id == transaction_id)
        )

    async def next_serial(self, clinic_id: UUID) -> int:
        current = await self.session.scalar(
            select(func.coalesce(func.max(TreatmentTransaction.serial_no), 0)).where(
                TreatmentTransaction.clinic_id == clinic_id
            )
        )
        return int(current or 0) + 1

    async def list_filtered(
        self,
        clinic_id: UUID,
        *,
        from_date: date | None,
        to_date: date | None,
        treatment_id: UUID | None,
        category_id: UUID | None,
        search: str | None,
        page: int,
        page_size: int,
        sort: str | None,
        patient_id: UUID | None = None,
    ) -> tuple[list[TreatmentTransaction], int]:
        stmt = self._base(clinic_id).options(*_visit_options())
        if from_date:
            stmt = stmt.where(TreatmentTransaction.transaction_date >= from_date)
        if to_date:
            stmt = stmt.where(TreatmentTransaction.transaction_date <= to_date)
        if treatment_id:
            stmt = stmt.where(TreatmentTransaction.treatment_id == treatment_id)
        if patient_id:
            stmt = stmt.where(TreatmentTransaction.patient_id == patient_id)
        if category_id or search:
            stmt = stmt.join(Treatment, Treatment.id == TreatmentTransaction.treatment_id)
        if category_id:
            stmt = stmt.where(Treatment.category_id == category_id)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.outerjoin(Patient, Patient.id == TreatmentTransaction.patient_id)
            stmt = stmt.where(
                or_(
                    TreatmentTransaction.notes.ilike(pattern),
                    TreatmentTransaction.sub_treatment.ilike(pattern),
                    Treatment.name.ilike(pattern),
                    Patient.name.ilike(pattern),
                )
            )
        stmt = apply_sort(
            stmt,
            TreatmentTransaction,
            sort,
            "-transaction_date",
            {"transaction_date", "amount", "created_at", "quantity", "serial_no"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total
