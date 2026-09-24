import uuid
from decimal import Decimal

from pydantic import EmailStr, Field, field_serializer, field_validator

from app.schemas.common import APIModel
from app.utils.money import format_money


class LoginRequest(APIModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)
    device_id: str = Field(min_length=1, max_length=128)
    device_name: str | None = Field(default=None, max_length=150)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return str(value).strip().lower()


class RefreshRequest(APIModel):
    refresh_token: str = Field(min_length=1)
    device_id: str | None = Field(default=None, max_length=128)


class LogoutRequest(APIModel):
    refresh_token: str = Field(min_length=1)


class ChangePasswordRequest(APIModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=10, max_length=128)


class ClinicPublic(APIModel):
    id: uuid.UUID
    name: str
    currency: str
    timezone: str


class UserPublic(APIModel):
    id: uuid.UUID
    full_name: str
    email: str
    role: str
    default_home_budget: Decimal
    has_avatar: bool = False

    @field_serializer("default_home_budget")
    def serialize_budget(self, value: Decimal) -> str:
        return format_money(value)


class LoginResponse(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserPublic
    clinic: ClinicPublic


class TokenRefreshResponse(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class MeResponse(APIModel):
    user: UserPublic
    clinic: ClinicPublic
