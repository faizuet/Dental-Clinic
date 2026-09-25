import json
import uuid
from datetime import date
from typing import Any

from pydantic import Field, field_validator

from app.core.config import settings
from app.schemas.common import VersionedRead
from app.utils.money import MoneyPositive
from app.utils.pagination import APIModel


def _trim(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


def _normalize_details(value: dict[str, Any] | None) -> dict[str, Any]:
    data = value or {}
    if not isinstance(data, dict):
        raise ValueError("Treatment details must be a set of fields.")
    raw = json.dumps(data, default=str)
    if len(raw) > 8000:
        raise ValueError("Treatment details are too long.")
    return data


class TreatmentAttachmentRead(VersionedRead):
    clinic_id: uuid.UUID
    transaction_id: uuid.UUID
    label: str
    original_name: str | None = None
    content_type: str
    byte_size: int


class TreatmentTransactionCreate(APIModel):
    id: uuid.UUID | None = None
    treatment_id: uuid.UUID
    transaction_date: date
    quantity: int = Field(default=1, ge=1, le=999)
    amount: MoneyPositive
    notes: str | None = Field(default=None, max_length=1000)
    patient_id: uuid.UUID | None = None
    sub_treatment: str | None = Field(default=None, max_length=150)
    details: dict[str, Any] = Field(default_factory=dict)

    @field_validator("notes", "sub_treatment")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        return _trim(value)

    @field_validator("details")
    @classmethod
    def clean_details(cls, value: dict[str, Any] | None) -> dict[str, Any]:
        return _normalize_details(value)


class TreatmentTransactionUpdate(APIModel):
    version: int = Field(ge=1)
    treatment_id: uuid.UUID | None = None
    transaction_date: date | None = None
    quantity: int | None = Field(default=None, ge=1, le=999)
    amount: MoneyPositive | None = None
    notes: str | None = Field(default=None, max_length=1000)
    patient_id: uuid.UUID | None = None
    sub_treatment: str | None = Field(default=None, max_length=150)
    details: dict[str, Any] | None = None

    @field_validator("notes", "sub_treatment")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        return _trim(value)

    @field_validator("details")
    @classmethod
    def clean_details(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        if value is None:
            return None
        return _normalize_details(value)


class TreatmentTransactionBatchCreate(APIModel):
    items: list[TreatmentTransactionCreate] = Field(min_length=1, max_length=settings.BATCH_MAX_ITEMS)


class TreatmentTransactionRead(VersionedRead):
    clinic_id: uuid.UUID
    treatment_id: uuid.UUID
    created_by: uuid.UUID
    transaction_date: date
    quantity: int
    amount: MoneyPositive
    notes: str | None = None
    patient_id: uuid.UUID | None = None
    serial_no: int | None = None
    sub_treatment: str | None = None
    details: dict[str, Any] = Field(default_factory=dict)
    patient_name: str | None = None
    patient_phone: str | None = None
    treatment_name: str | None = None
    category_name: str | None = None
    details_text: str | None = None
    attachments: list[TreatmentAttachmentRead] = Field(default_factory=list)
