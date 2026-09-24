import base64
import json
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import SyncEntity, SyncItemStatus, SyncOperation
from app.core.exceptions import AppError, ConflictError, VersionConflictError
from app.models import (
    ClinicExpense,
    ClinicExpenseCategory,
    ConstructionMaterial,
    ConstructionMaterialCategory,
    ConstructionPurchase,
    HomeBudget,
    HomeExpense,
    HomeExpenseCategory,
    Treatment,
    TreatmentCategory,
    TreatmentTransaction,
    User,
)
from app.models.mixins import utc_now
from app.models.sync_change import SyncChange
from app.repositories.sync import SyncChangeRepository
from app.schemas.clinic_expense import ClinicExpenseCreate, ClinicExpenseRead, ClinicExpenseUpdate
from app.schemas.clinic_expense_category import (
    ClinicExpenseCategoryCreate,
    ClinicExpenseCategoryRead,
    ClinicExpenseCategoryUpdate,
)
from app.schemas.home_budget import HomeBudgetCreate, HomeBudgetRead, HomeBudgetUpdate
from app.schemas.home_expense import HomeExpenseCreate, HomeExpenseRead, HomeExpenseUpdate
from app.schemas.home_expense_category import (
    HomeExpenseCategoryCreate,
    HomeExpenseCategoryRead,
    HomeExpenseCategoryUpdate,
)
from app.schemas.construction import (
    ConstructionMaterialCategoryCreate,
    ConstructionMaterialCategoryRead,
    ConstructionMaterialCategoryUpdate,
    ConstructionMaterialCreate,
    ConstructionMaterialRead,
    ConstructionMaterialUpdate,
    ConstructionPurchaseCreate,
    ConstructionPurchaseRead,
    ConstructionPurchaseUpdate,
)
from app.schemas.sync import SyncChangeIn, SyncPushRequest, SyncPushResponse, SyncPushResult
from app.schemas.treatment import TreatmentCreate, TreatmentRead, TreatmentUpdate
from app.schemas.treatment_category import TreatmentCategoryCreate, TreatmentCategoryRead, TreatmentCategoryUpdate
from app.schemas.treatment_transaction import (
    TreatmentTransactionCreate,
    TreatmentTransactionRead,
    TreatmentTransactionUpdate,
)
from app.services.clinic_expense_service import ClinicExpenseService
from app.services.construction_service import ConstructionService
from app.services.home_expense_service import HomeExpenseService
from app.services.treatment_service import TreatmentService
from app.utils.dates import serialize_datetime

ENTITY_KEYS = {
    SyncEntity.TREATMENT_CATEGORY: "treatment_categories",
    SyncEntity.TREATMENT: "treatments",
    SyncEntity.TREATMENT_TRANSACTION: "treatment_transactions",
    SyncEntity.CLINIC_EXPENSE_CATEGORY: "clinic_expense_categories",
    SyncEntity.CLINIC_EXPENSE: "clinic_expenses",
    SyncEntity.HOME_EXPENSE_CATEGORY: "home_expense_categories",
    SyncEntity.HOME_EXPENSE: "home_expenses",
    SyncEntity.HOME_BUDGET: "home_budgets",
    SyncEntity.CONSTRUCTION_MATERIAL_CATEGORY: "construction_material_categories",
    SyncEntity.CONSTRUCTION_MATERIAL: "construction_materials",
    SyncEntity.CONSTRUCTION_PURCHASE: "construction_purchases",
}

READERS = {
    SyncEntity.TREATMENT_CATEGORY: TreatmentCategoryRead,
    SyncEntity.TREATMENT: TreatmentRead,
    SyncEntity.TREATMENT_TRANSACTION: TreatmentTransactionRead,
    SyncEntity.CLINIC_EXPENSE_CATEGORY: ClinicExpenseCategoryRead,
    SyncEntity.CLINIC_EXPENSE: ClinicExpenseRead,
    SyncEntity.HOME_EXPENSE_CATEGORY: HomeExpenseCategoryRead,
    SyncEntity.HOME_EXPENSE: HomeExpenseRead,
    SyncEntity.HOME_BUDGET: HomeBudgetRead,
    SyncEntity.CONSTRUCTION_MATERIAL_CATEGORY: ConstructionMaterialCategoryRead,
    SyncEntity.CONSTRUCTION_MATERIAL: ConstructionMaterialRead,
    SyncEntity.CONSTRUCTION_PURCHASE: ConstructionPurchaseRead,
}

MODELS = {
    SyncEntity.TREATMENT_CATEGORY: TreatmentCategory,
    SyncEntity.TREATMENT: Treatment,
    SyncEntity.TREATMENT_TRANSACTION: TreatmentTransaction,
    SyncEntity.CLINIC_EXPENSE_CATEGORY: ClinicExpenseCategory,
    SyncEntity.CLINIC_EXPENSE: ClinicExpense,
    SyncEntity.HOME_EXPENSE_CATEGORY: HomeExpenseCategory,
    SyncEntity.HOME_EXPENSE: HomeExpense,
    SyncEntity.HOME_BUDGET: HomeBudget,
    SyncEntity.CONSTRUCTION_MATERIAL_CATEGORY: ConstructionMaterialCategory,
    SyncEntity.CONSTRUCTION_MATERIAL: ConstructionMaterial,
    SyncEntity.CONSTRUCTION_PURCHASE: ConstructionPurchase,
}


class SyncService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.changes = SyncChangeRepository(session)
        self.treatments = TreatmentService(session)
        self.clinic_expenses = ClinicExpenseService(session)
        self.home = HomeExpenseService(session)
        self.construction = ConstructionService(session)

    async def push(self, user: User, payload: SyncPushRequest) -> SyncPushResponse:
        results: list[SyncPushResult] = []
        for change in payload.changes:
            result = await self._apply_change(user, payload.device_id, change)
            results.append(result)
        return SyncPushResponse(results=results, server_time=utc_now())

    async def pull(self, user: User, *, cursor: str | None, limit: int) -> dict[str, Any]:
        state = decode_cursor(cursor)
        changes: dict[str, list[dict[str, Any]]] = {}
        new_state: dict[str, tuple[datetime, uuid.UUID]] = dict(state)
        for entity, key in ENTITY_KEYS.items():
            records = await self._pull_entity(user, entity, state.get(entity.value), limit)
            dumped = [dump_record(entity, record) for record in records]
            changes[key] = dumped
            if records:
                last = records[-1]
                new_state[entity.value] = (last.updated_at, last.id)
        return {
            "changes": changes,
            "next_cursor": encode_cursor(new_state) if new_state else None,
            "server_time": utc_now(),
        }

    async def bootstrap(self, user: User) -> dict[str, Any]:
        data: dict[str, list[dict[str, Any]]] = {}
        state: dict[str, tuple[datetime, uuid.UUID]] = {}
        for entity, key in ENTITY_KEYS.items():
            records = await self._pull_entity(user, entity, None, 10_000, live_only=True)
            data[key] = [dump_record(entity, record) for record in records]
            latest = await self._latest(user, entity)
            if latest:
                state[entity.value] = (latest.updated_at, latest.id)
        return {
            "clinic": {
                "id": str(user.clinic.id),
                "name": user.clinic.name,
                "currency": user.clinic.currency,
                "timezone": user.clinic.timezone,
            },
            "user": {
                "id": str(user.id),
                "full_name": user.full_name,
                "email": user.email,
                "role": user.role,
                "default_home_budget": f"{user.default_home_budget:.2f}",
            },
            "data": data,
            "cursor": encode_cursor(state) if state else None,
            "server_time": utc_now(),
        }

    async def _apply_change(self, user: User, device_id: str, change: SyncChangeIn) -> SyncPushResult:
        existing = await self.changes.get_by_client_change_id(change.client_change_id)
        if existing:
            payload = existing.result
            return SyncPushResult(
                client_change_id=change.client_change_id,
                status=payload.get("status", SyncItemStatus.APPLIED),
                record=payload.get("record"),
                error=payload.get("error"),
            )
        try:
            async with self.session.begin_nested():
                record = await self._dispatch(user, change)
                dumped = dump_record(change.entity, record) if record is not None else None
                result = {
                    "status": "applied",
                    "record": dumped,
                    "error": None,
                }
        except VersionConflictError as exc:
            dumped = dump_record(change.entity, exc.extra["record"]) if exc.extra.get("record") else None
            result = {"status": "conflict", "record": dumped, "error": {"code": exc.code, "message": exc.message}}
        except AppError as exc:
            result = {
                "status": "failed",
                "record": None,
                "error": {"code": exc.code, "message": exc.message, "details": exc.details},
            }
        except Exception:
            result = {
                "status": "failed",
                "record": None,
                "error": {"code": "INTERNAL_ERROR", "message": "The change could not be applied."},
            }
        self.session.add(
            SyncChange(
                client_change_id=change.client_change_id,
                user_id=user.id,
                device_id=device_id,
                entity_type=change.entity,
                entity_id=change.entity_id,
                operation=change.operation,
                status=result["status"],
                result=result,
            )
        )
        await self.session.flush()
        return SyncPushResult(
            client_change_id=change.client_change_id,
            status=result["status"],
            record=result.get("record"),
            error=result.get("error"),
        )

    async def _dispatch(self, user: User, change: SyncChangeIn):
        data = dict(change.data)
        data["id"] = str(change.entity_id)
        if change.operation == SyncOperation.UPDATE:
            data["version"] = change.base_version
        if change.operation == SyncOperation.DELETE and change.base_version is None:
            raise VersionConflictError("Updates and deletes require base_version.")

        entity = change.entity
        if entity == SyncEntity.TREATMENT_CATEGORY:
            return await self._mut_category(user, change, data)
        if entity == SyncEntity.TREATMENT:
            return await self._mut_treatment(user, change, data)
        if entity == SyncEntity.TREATMENT_TRANSACTION:
            return await self._mut_tx(user, change, data)
        if entity == SyncEntity.CLINIC_EXPENSE_CATEGORY:
            return await self._mut_clinic_category(user, change, data)
        if entity == SyncEntity.CLINIC_EXPENSE:
            return await self._mut_clinic_expense(user, change, data)
        if entity == SyncEntity.HOME_EXPENSE_CATEGORY:
            return await self._mut_home_category(user, change, data)
        if entity == SyncEntity.HOME_EXPENSE:
            return await self._mut_home_expense(user, change, data)
        if entity == SyncEntity.HOME_BUDGET:
            return await self._mut_home_budget(user, change, data)
        if entity == SyncEntity.CONSTRUCTION_MATERIAL_CATEGORY:
            return await self._mut_construction_category(user, change, data)
        if entity == SyncEntity.CONSTRUCTION_MATERIAL:
            return await self._mut_construction_material(user, change, data)
        if entity == SyncEntity.CONSTRUCTION_PURCHASE:
            return await self._mut_construction_purchase(user, change, data)
        raise ConflictError("Unsupported sync entity.")

    async def _mut_category(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = TreatmentCategoryCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.treatments.create_category(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.treatments.update_category(
                user, change.entity_id, TreatmentCategoryUpdate.model_validate(data)
            )
        return await self.treatments.delete_category(user, change.entity_id, change.base_version or 1)

    async def _mut_treatment(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = TreatmentCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.treatments.create_treatment(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.treatments.update_treatment(user, change.entity_id, TreatmentUpdate.model_validate(data))
        return await self.treatments.delete_treatment(user, change.entity_id, change.base_version or 1)

    async def _mut_tx(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = TreatmentTransactionCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.treatments.create_transaction(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.treatments.update_transaction(
                user, change.entity_id, TreatmentTransactionUpdate.model_validate(data)
            )
        return await self.treatments.delete_transaction(user, change.entity_id, change.base_version or 1)

    async def _mut_clinic_category(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = ClinicExpenseCategoryCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.clinic_expenses.create_category(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.clinic_expenses.update_category(
                user, change.entity_id, ClinicExpenseCategoryUpdate.model_validate(data)
            )
        return await self.clinic_expenses.delete_category(user, change.entity_id, change.base_version or 1)

    async def _mut_clinic_expense(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = ClinicExpenseCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.clinic_expenses.create_expense(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.clinic_expenses.update_expense(
                user, change.entity_id, ClinicExpenseUpdate.model_validate(data)
            )
        return await self.clinic_expenses.delete_expense(user, change.entity_id, change.base_version or 1)

    async def _mut_home_category(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = HomeExpenseCategoryCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.home.create_category(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.home.update_category(
                user, change.entity_id, HomeExpenseCategoryUpdate.model_validate(data)
            )
        return await self.home.delete_category(user, change.entity_id, change.base_version or 1)

    async def _mut_home_expense(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = HomeExpenseCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.home.create_expense(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.home.update_expense(user, change.entity_id, HomeExpenseUpdate.model_validate(data))
        return await self.home.delete_expense(user, change.entity_id, change.base_version or 1)

    async def _mut_home_budget(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = HomeBudgetCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.home.create_budget(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.home.update_budget(user, change.entity_id, HomeBudgetUpdate.model_validate(data))
        return await self.home.delete_budget(user, change.entity_id, change.base_version or 1)

    async def _mut_construction_category(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = ConstructionMaterialCategoryCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.construction.create_category(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.construction.update_category(
                user, change.entity_id, ConstructionMaterialCategoryUpdate.model_validate(data)
            )
        return await self.construction.delete_category(user, change.entity_id, change.base_version or 1)

    async def _mut_construction_material(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = ConstructionMaterialCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.construction.create_material(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.construction.update_material(
                user, change.entity_id, ConstructionMaterialUpdate.model_validate(data)
            )
        return await self.construction.delete_material(user, change.entity_id, change.base_version or 1)

    async def _mut_construction_purchase(self, user, change, data):
        if change.operation == SyncOperation.CREATE:
            payload = ConstructionPurchaseCreate.model_validate(data)
            payload.id = change.entity_id
            return await self.construction.create_purchase(user, payload)
        if change.operation == SyncOperation.UPDATE:
            return await self.construction.update_purchase(
                user, change.entity_id, ConstructionPurchaseUpdate.model_validate(data)
            )
        return await self.construction.delete_purchase(user, change.entity_id, change.base_version or 1)

    async def _pull_entity(
        self,
        user: User,
        entity: SyncEntity,
        cursor_pos: tuple[datetime, uuid.UUID] | None,
        limit: int,
        live_only: bool = False,
    ):
        model = MODELS[entity]
        stmt = select(model)
        if entity.value.startswith("home_") or entity.value.startswith("construction_"):
            stmt = stmt.where(model.user_id == user.id)
        else:
            stmt = stmt.where(model.clinic_id == user.clinic_id)
        if live_only:
            stmt = stmt.where(model.deleted_at.is_(None))
        if cursor_pos:
            ts, rid = cursor_pos
            stmt = stmt.where(or_(model.updated_at > ts, and_(model.updated_at == ts, model.id > rid)))
        stmt = stmt.order_by(model.updated_at.asc(), model.id.asc()).limit(limit)
        return list((await self.session.scalars(stmt)).all())

    async def _latest(self, user: User, entity: SyncEntity):
        model = MODELS[entity]
        stmt = select(model)
        if entity.value.startswith("home_") or entity.value.startswith("construction_"):
            stmt = stmt.where(model.user_id == user.id)
        else:
            stmt = stmt.where(model.clinic_id == user.clinic_id)
        stmt = stmt.order_by(model.updated_at.desc(), model.id.desc()).limit(1)
        return await self.session.scalar(stmt)


def dump_record(entity: SyncEntity, record: Any) -> dict[str, Any]:
    return READERS[entity].model_validate(record).model_dump(mode="json")


def encode_cursor(state: dict[str, tuple[datetime, uuid.UUID]]) -> str:
    payload = {
        key if isinstance(key, str) else key.value: f"{serialize_datetime(ts)}|{rid}"
        for key, (ts, rid) in state.items()
    }
    return base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("ascii")


def decode_cursor(cursor: str | None) -> dict[str, tuple[datetime, uuid.UUID]]:
    if not cursor:
        return {}
    raw = json.loads(base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8"))
    parsed: dict[str, tuple[datetime, uuid.UUID]] = {}
    for key, value in raw.items():
        stamp, rid = value.split("|", 1)
        parsed[key] = (datetime.fromisoformat(stamp.replace("Z", "+00:00")), uuid.UUID(rid))
    return parsed
