from collections.abc import Sequence
from typing import Any
from uuid import UUID

from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import InstrumentedAttribute

from app.core.exceptions import NotFoundError, VersionConflictError


class BaseRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def scalar(self, stmt: Select[Any]) -> Any:
        return await self.session.scalar(stmt)

    async def scalars(self, stmt: Select[Any]) -> Sequence[Any]:
        result = await self.session.scalars(stmt)
        return result.all()

    async def paginate(self, stmt: Select[Any], *, page: int, page_size: int) -> tuple[Sequence[Any], int]:
        count_stmt = select(func.count()).select_from(stmt.order_by(None).subquery())
        total = int(await self.session.scalar(count_stmt) or 0)
        items = (await self.session.scalars(stmt.offset((page - 1) * page_size).limit(page_size))).all()
        return items, total

    async def add(self, instance: Any) -> Any:
        self.session.add(instance)
        await self.session.flush()
        await self.session.refresh(instance)
        return instance

    async def max_order(self, column: InstrumentedAttribute[int], *where: Any) -> int:
        value = await self.session.scalar(select(func.coalesce(func.max(column), -1)).where(*where))
        return int(value) + 1


def apply_sort(stmt: Select[Any], model: Any, sort: str | None, default: str, allowed: set[str]) -> Select[Any]:
    raw = sort or default
    descending = raw.startswith("-")
    field_name = raw[1:] if descending else raw
    if field_name not in allowed:
        field_name = default[1:] if default.startswith("-") else default
        descending = default.startswith("-")
    column = getattr(model, field_name)
    order = column.desc() if descending else column.asc()
    return stmt.order_by(order, model.id.desc())


def ensure_version(record: Any, expected: int) -> None:
    if record.version != expected:
        raise VersionConflictError(record=record)


def require_record(record: Any, message: str = "The requested resource was not found.") -> Any:
    if record is None or getattr(record, "deleted_at", None) is not None:
        raise NotFoundError(message)
    return record


def as_uuid(value: UUID | str) -> UUID:
    return value if isinstance(value, UUID) else UUID(str(value))
