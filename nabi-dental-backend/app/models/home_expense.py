import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import CheckConstraint, Date, ForeignKey, Numeric, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import UUIDPrimaryKeyMixin, VersionedMixin
from app.models.home_expense_category import HomeExpenseCategory


class HomeExpense(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "home_expenses"
    __table_args__ = (CheckConstraint("amount > 0", name="ck_home_expenses_amount_positive"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        index=True,
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("home_expense_categories.id"),
        nullable=False,
        index=True,
    )
    expense_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)

    category: Mapped[HomeExpenseCategory] = relationship(back_populates="expenses")
