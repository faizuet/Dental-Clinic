import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import Boolean, CheckConstraint, Date, ForeignKey, Integer, Numeric, String, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import UUIDPrimaryKeyMixin, VersionedMixin


class ConstructionMaterialCategory(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "construction_material_categories"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    display_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))

    materials: Mapped[list["ConstructionMaterial"]] = relationship(back_populates="category")


class ConstructionMaterial(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "construction_materials"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        index=True,
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("construction_material_categories.id"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    unit: Mapped[str] = mapped_column(String(30), nullable=False, server_default=text("'piece'"))
    display_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))

    category: Mapped[ConstructionMaterialCategory] = relationship(back_populates="materials")
    purchases: Mapped[list["ConstructionPurchase"]] = relationship(back_populates="material")


class ConstructionPurchase(UUIDPrimaryKeyMixin, VersionedMixin, Base):
    __tablename__ = "construction_purchases"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_construction_purchases_quantity_positive"),
        CheckConstraint("unit_price > 0", name="ck_construction_purchases_unit_price_positive"),
        CheckConstraint("amount > 0", name="ck_construction_purchases_amount_positive"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        index=True,
    )
    material_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("construction_materials.id"),
        nullable=False,
        index=True,
    )
    purchase_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    unit: Mapped[str] = mapped_column(String(30), nullable=False)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    supplier: Mapped[str | None] = mapped_column(String(150), nullable=True)
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)

    material: Mapped[ConstructionMaterial] = relationship(back_populates="purchases")
