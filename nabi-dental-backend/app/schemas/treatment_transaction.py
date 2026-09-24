import uuid
from datetime import date

from pydantic import Field, field_validator

from app.core.config import settings
from app.schemas.common import VersionedRead
from app.utils.money import MoneyPositive
from app.utils.pagination import APIModel


class TreatmentTransactionCreate(APIModel):
    id: uuid.UUID | None = None
    treatment_id: uuid.UUID
    transaction_date: date
    quantity: int = Field(default=1, ge=1, le=999)
    amount: MoneyPositive
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("notes")
    @classmethod
    def trim_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class TreatmentTransactionUpdate(APIModel):
    version: int = Field(ge=1)
    treatment_id: uuid.UUID | None = None
    transaction_date: date | None = None
    quantity: int | None = Field(default=None, ge=1, le=999)
    amount: MoneyPositive | None = None
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("notes")
    @classmethod
    def trim_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class TreatmentTransactionBatchCreate(APIModel):
    items: list[TreatmentTransactionCreate] = Field(min_length=1, max_length=settings.BATCH_MAX_ITEMS)


class TreatmentTransactionRead(VersionedRead):
    clinic_id: uuid.UUID
    treatment_id: uuid.UUID
    created_by: uuid.UUID
    transaction_date: date
    quantity: int
    amount: MoneyPositive
    notes: str | None
