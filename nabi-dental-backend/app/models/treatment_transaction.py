import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import CheckConstraint, Date, ForeignKey, Integer, Numeric, String, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import UUIDPrimaryKeyMixin, VersionedMixin
from app.models.patient import Patient
from app.models.treatment import Treatment
from app.models.treatment_attachment import TreatmentAttachment


class TreatmentTransaction(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "treatment_transactions"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_treatment_transactions_quantity_positive"),
        CheckConstraint("amount > 0", name="ck_treatment_transactions_amount_positive"),
    )

    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("clinics.id"),
        nullable=False,
        index=True,
    )
    treatment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("treatments.id"),
        nullable=False,
        index=True,
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    patient_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("patients.id"),
        nullable=True,
        index=True,
    )
    serial_no: Mapped[int] = mapped_column(Integer, nullable=False)
    transaction_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("1"))
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    sub_treatment: Mapped[str | None] = mapped_column(String(150), nullable=True)
    details: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict, server_default=text("'{}'::jsonb"))
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)

    treatment: Mapped[Treatment] = relationship(back_populates="transactions")
    patient: Mapped[Patient | None] = relationship(back_populates="treatments")
    attachments: Mapped[list[TreatmentAttachment]] = relationship(back_populates="transaction")
