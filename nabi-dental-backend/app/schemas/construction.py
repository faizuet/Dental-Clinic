import uuid
from datetime import date
from decimal import Decimal

from pydantic import Field, field_serializer, field_validator

from app.core.config import settings
from app.schemas.common import VersionedRead
from app.utils.money import MoneyPositive, QuantityPositive, format_money, format_quantity
from app.utils.pagination import APIModel


def _trim_optional(value: str | None, *, empty_message: str | None = None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        if empty_message:
            raise ValueError(empty_message)
        return None
    return cleaned


class ConstructionMaterialCategoryCreate(APIModel):
    id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=120)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool = True

    @field_validator("name")
    @classmethod
    def trim_name(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Name is required.")
        return cleaned


class ConstructionMaterialCategoryUpdate(APIModel):
    version: int = Field(ge=1)
    name: str | None = Field(default=None, min_length=1, max_length=120)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool | None = None

    @field_validator("name")
    @classmethod
    def trim_name(cls, value: str | None) -> str | None:
        return _trim_optional(value, empty_message="Name is required.")


class ConstructionMaterialCategoryRead(VersionedRead):
    user_id: uuid.UUID
    name: str
    display_order: int
    is_active: bool


class ConstructionMaterialCreate(APIModel):
    id: uuid.UUID | None = None
    category_id: uuid.UUID
    name: str = Field(min_length=1, max_length=150)
    unit: str = Field(min_length=1, max_length=30)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool = True

    @field_validator("name", "unit")
    @classmethod
    def trim_required(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("This field is required.")
        return cleaned


class ConstructionMaterialUpdate(APIModel):
    version: int = Field(ge=1)
    category_id: uuid.UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=150)
    unit: str | None = Field(default=None, min_length=1, max_length=30)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool | None = None

    @field_validator("name", "unit")
    @classmethod
    def trim_optional(cls, value: str | None) -> str | None:
        return _trim_optional(value, empty_message="This field is required.")


class ConstructionMaterialRead(VersionedRead):
    user_id: uuid.UUID
    category_id: uuid.UUID
    name: str
    unit: str
    display_order: int
    is_active: bool


class ConstructionPurchaseCreate(APIModel):
    id: uuid.UUID | None = None
    material_id: uuid.UUID
    purchase_date: date
    quantity: QuantityPositive
    unit: str | None = Field(default=None, max_length=30)
    unit_price: MoneyPositive
    supplier: str | None = Field(default=None, max_length=150)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("unit", "supplier", "notes")
    @classmethod
    def trim_optional_text(cls, value: str | None) -> str | None:
        return _trim_optional(value)


class ConstructionPurchaseUpdate(APIModel):
    version: int = Field(ge=1)
    material_id: uuid.UUID | None = None
    purchase_date: date | None = None
    quantity: QuantityPositive | None = None
    unit: str | None = Field(default=None, max_length=30)
    unit_price: MoneyPositive | None = None
    supplier: str | None = Field(default=None, max_length=150)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("unit", "supplier", "notes")
    @classmethod
    def trim_optional_text(cls, value: str | None) -> str | None:
        return _trim_optional(value)


class ConstructionPurchaseBatchCreate(APIModel):
    items: list[ConstructionPurchaseCreate] = Field(min_length=1, max_length=settings.BATCH_MAX_ITEMS)


class ConstructionPurchaseRead(VersionedRead):
    user_id: uuid.UUID
    material_id: uuid.UUID
    purchase_date: date
    quantity: Decimal
    unit: str
    unit_price: Decimal
    amount: Decimal
    supplier: str | None
    notes: str | None

    @field_serializer("quantity")
    def serialize_quantity(self, value: Decimal) -> str:
        return format_quantity(value)

    @field_serializer("unit_price", "amount")
    def serialize_money(self, value: Decimal) -> str:
        return format_money(value)
