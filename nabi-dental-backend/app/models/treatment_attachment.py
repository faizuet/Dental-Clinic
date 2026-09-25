import uuid

from sqlalchemy import ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import UUIDPrimaryKeyMixin, VersionedMixin


class TreatmentAttachment(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "treatment_attachments"

    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("clinics.id"),
        nullable=False,
        index=True,
    )
    transaction_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("treatment_transactions.id"),
        nullable=False,
        index=True,
    )
    stored_path: Mapped[str] = mapped_column(String(500), nullable=False)
    original_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    label: Mapped[str] = mapped_column(String(40), nullable=False, default="other")
    content_type: Mapped[str] = mapped_column(String(80), nullable=False, default="image/jpeg")
    byte_size: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    transaction: Mapped["TreatmentTransaction"] = relationship(back_populates="attachments")
