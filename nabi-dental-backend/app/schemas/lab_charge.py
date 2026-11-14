import uuid
from datetime import date

from pydantic import Field, field_validator

from app.schemas.common import VersionedRead
from app.utils.money import MoneyPositive
from app.utils.pagination import APIModel


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


class LabChargeCreate(APIModel):
    id: uuid.UUID | None = None
    charge_date: date
    amount: MoneyPositive
    patient_id: uuid.UUID | None = None
    transaction_id: uuid.UUID | None = None
    lab_name: str | None = Field(default=None, max_length=150)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("lab_name", "notes")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        return _clean(value)


class LabChargeUpdate(APIModel):
    version: int = Field(ge=1)
    charge_date: date | None = None
    amount: MoneyPositive | None = None
    patient_id: uuid.UUID | None = None
    transaction_id: uuid.UUID | None = None
    lab_name: str | None = Field(default=None, max_length=150)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("lab_name", "notes")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        return _clean(value)


class LabChargeRead(VersionedRead):
    clinic_id: uuid.UUID
    created_by: uuid.UUID
    charge_date: date
    amount: MoneyPositive
    patient_id: uuid.UUID | None
    transaction_id: uuid.UUID | None
    lab_name: str | None
    notes: str | None
