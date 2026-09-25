import uuid

from pydantic import Field, field_validator

from app.schemas.common import VersionedRead
from app.utils.pagination import APIModel


def _trim(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


class PatientCreate(APIModel):
    id: uuid.UUID | None = None
    name: str = Field(min_length=2, max_length=150)
    phone: str | None = Field(default=None, max_length=40)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        cleaned = value.strip()
        if len(cleaned) < 2:
            raise ValueError("Enter the patient name.")
        return cleaned

    @field_validator("phone", "notes")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        return _trim(value)


class PatientUpdate(APIModel):
    version: int = Field(ge=1)
    name: str | None = Field(default=None, min_length=2, max_length=150)
    phone: str | None = Field(default=None, max_length=40)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if len(cleaned) < 2:
            raise ValueError("Enter the patient name.")
        return cleaned

    @field_validator("phone", "notes")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        return _trim(value)


class PatientRead(VersionedRead):
    clinic_id: uuid.UUID
    name: str
    phone: str | None = None
    notes: str | None = None
