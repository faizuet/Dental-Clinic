import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import Field, field_serializer

from app.core.config import settings
from app.core.constants import SyncEntity, SyncOperation
from app.utils.dates import serialize_datetime
from app.utils.pagination import APIModel


class SyncChangeIn(APIModel):
    client_change_id: uuid.UUID
    entity: SyncEntity
    operation: SyncOperation
    entity_id: uuid.UUID
    base_version: int | None = Field(default=None, ge=1)
    data: dict[str, Any] = Field(default_factory=dict)


class SyncPushRequest(APIModel):
    device_id: str = Field(min_length=1, max_length=128)
    changes: list[SyncChangeIn] = Field(min_length=1, max_length=settings.SYNC_PUSH_MAX_CHANGES)


class SyncPushResult(APIModel):
    client_change_id: uuid.UUID
    status: Literal["applied", "conflict", "failed"]
    record: dict[str, Any] | None = None
    error: dict[str, Any] | None = None


class SyncPushResponse(APIModel):
    results: list[SyncPushResult]
    server_time: datetime

    @field_serializer("server_time")
    def serialize_server_time(self, value: datetime) -> str:
        return serialize_datetime(value)


class SyncPullResponse(APIModel):
    changes: dict[str, list[dict[str, Any]]]
    next_cursor: str | None
    server_time: datetime

    @field_serializer("server_time")
    def serialize_server_time(self, value: datetime) -> str:
        return serialize_datetime(value)


class SyncBootstrapResponse(APIModel):
    clinic: dict[str, Any]
    user: dict[str, Any]
    data: dict[str, list[dict[str, Any]]]
    cursor: str | None
    server_time: datetime

    @field_serializer("server_time")
    def serialize_server_time(self, value: datetime) -> str:
        return serialize_datetime(value)
