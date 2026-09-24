import uuid
from decimal import Decimal

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, SmallInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import UUIDPrimaryKeyMixin, VersionedMixin


class HomeBudget(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "home_budgets"
    __table_args__ = (
        CheckConstraint("month >= 1 AND month <= 12", name="ck_home_budgets_month_range"),
        CheckConstraint("amount >= 0", name="ck_home_budgets_amount_non_negative"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        index=True,
    )
    year: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    month: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
