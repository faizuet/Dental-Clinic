from decimal import Decimal

from pydantic import Field, field_serializer, field_validator

from app.utils.dates import parse_timezone
from app.utils.money import MoneyNonNegative, format_money
from app.utils.pagination import APIModel


class SettingsUpdate(APIModel):
    clinic_name: str | None = Field(default=None, min_length=1, max_length=150)
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    full_name: str | None = Field(default=None, min_length=1, max_length=150)
    default_home_budget: MoneyNonNegative | None = None

    @field_validator("clinic_name", "full_name")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("This field cannot be empty.")
        return cleaned

    @field_validator("currency")
    @classmethod
    def currency_code(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip().upper()
        if len(cleaned) != 3 or not cleaned.isalpha():
            raise ValueError("Currency must be an ISO 4217 three-letter code.")
        return cleaned

    @field_validator("timezone")
    @classmethod
    def valid_timezone(cls, value: str | None) -> str | None:
        if value is None:
            return None
        parse_timezone(value)
        return value


class SettingsRead(APIModel):
    clinic_id: str
    clinic_name: str
    currency: str
    timezone: str
    full_name: str
    email: str
    default_home_budget: Decimal
    has_avatar: bool = False

    @field_serializer("default_home_budget")
    def serialize_budget(self, value: Decimal) -> str:
        return format_money(value)
