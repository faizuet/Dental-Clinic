import uuid
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.constants import ErrorCode
from app.core.exceptions import ConflictError
from app.db.seed import seed_construction_catalog
from app.models import User
from app.models.construction import ConstructionMaterial, ConstructionMaterialCategory, ConstructionPurchase
from app.repositories.base import ensure_version, require_record
from app.repositories.construction import (
    ConstructionMaterialCategoryRepository,
    ConstructionMaterialRepository,
    ConstructionPurchaseRepository,
)
from app.schemas.construction import (
    ConstructionMaterialCategoryCreate,
    ConstructionMaterialCategoryUpdate,
    ConstructionMaterialCreate,
    ConstructionMaterialUpdate,
    ConstructionPurchaseCreate,
    ConstructionPurchaseUpdate,
)
from app.utils.dates import validate_business_date
from app.utils.money import TWO_PLACES


class ConstructionService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.categories = ConstructionMaterialCategoryRepository(session)
        self.materials = ConstructionMaterialRepository(session)
        self.purchases = ConstructionPurchaseRepository(session)

    async def list_categories(self, user: User, **filters):
        await seed_construction_catalog(self.session, user)
        return await self.categories.list_filtered(user.id, **filters)

    async def get_category(self, user: User, category_id: uuid.UUID) -> ConstructionMaterialCategory:
        return require_record(await self.categories.get(user.id, category_id))

    async def create_category(self, user: User, payload: ConstructionMaterialCategoryCreate) -> ConstructionMaterialCategory:
        if await self.categories.name_taken(user.id, payload.name):
            raise ConflictError("A construction category with this name already exists.")
        record = ConstructionMaterialCategory(
            id=payload.id or uuid.uuid4(),
            user_id=user.id,
            name=payload.name,
            display_order=payload.display_order
            if payload.display_order is not None
            else await self.categories.next_order(user.id),
            is_active=payload.is_active,
        )
        return await self.categories.add(record)

    async def update_category(
        self, user: User, category_id: uuid.UUID, payload: ConstructionMaterialCategoryUpdate
    ) -> ConstructionMaterialCategory:
        record = await self.get_category(user, category_id)
        ensure_version(record, payload.version)
        if payload.name and await self.categories.name_taken(user.id, payload.name, exclude_id=record.id):
            raise ConflictError("A construction category with this name already exists.")
        data = payload.model_dump(exclude_unset=True, exclude={"version"})
        for key, value in data.items():
            setattr(record, key, value)
        record.bump()
        await self.session.flush()
        return record

    async def delete_category(self, user: User, category_id: uuid.UUID, version: int) -> ConstructionMaterialCategory:
        record = await self.get_category(user, category_id)
        ensure_version(record, version)
        if await self.categories.has_materials(category_id):
            raise ConflictError(
                "This category has materials and cannot be deleted. Deactivate it instead.",
                code=ErrorCode.CATALOG_IN_USE,
            )
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_materials(self, user: User, **filters):
        await seed_construction_catalog(self.session, user)
        return await self.materials.list_filtered(user.id, **filters)

    async def get_material(self, user: User, material_id: uuid.UUID) -> ConstructionMaterial:
        return require_record(
            await self.materials.get(user.id, material_id),
            "This construction material is not available on the server. Sync the app and select it again.",
        )

    async def create_material(self, user: User, payload: ConstructionMaterialCreate) -> ConstructionMaterial:
        await self._require_active_category(user, payload.category_id)
        if await self.materials.name_taken(user.id, payload.name):
            raise ConflictError("A construction material with this name already exists.")
        record = ConstructionMaterial(
            id=payload.id or uuid.uuid4(),
            user_id=user.id,
            category_id=payload.category_id,
            name=payload.name,
            unit=payload.unit,
            display_order=payload.display_order
            if payload.display_order is not None
            else await self.materials.next_order(user.id),
            is_active=payload.is_active,
        )
        return await self.materials.add(record)

    async def update_material(
        self, user: User, material_id: uuid.UUID, payload: ConstructionMaterialUpdate
    ) -> ConstructionMaterial:
        record = await self.get_material(user, material_id)
        ensure_version(record, payload.version)
        if payload.category_id:
            await self._require_active_category(user, payload.category_id)
        if payload.name and await self.materials.name_taken(user.id, payload.name, exclude_id=record.id):
            raise ConflictError("A construction material with this name already exists.")
        data = payload.model_dump(exclude_unset=True, exclude={"version"})
        for key, value in data.items():
            setattr(record, key, value)
        record.bump()
        await self.session.flush()
        return record

    async def delete_material(self, user: User, material_id: uuid.UUID, version: int) -> ConstructionMaterial:
        record = await self.get_material(user, material_id)
        ensure_version(record, version)
        if await self.materials.has_purchases(material_id):
            raise ConflictError(
                "This material has purchase history and cannot be deleted. Deactivate it instead.",
                code=ErrorCode.CATALOG_IN_USE,
            )
        record.soft_delete()
        await self.session.flush()
        return record

    async def list_purchases(self, user: User, **filters):
        return await self.purchases.list_filtered(user.id, **filters)

    async def get_purchase(self, user: User, purchase_id: uuid.UUID) -> ConstructionPurchase:
        return require_record(await self.purchases.get(user.id, purchase_id))

    async def create_purchase(self, user: User, payload: ConstructionPurchaseCreate) -> ConstructionPurchase:
        return await self._build_purchase(user, payload)

    async def create_purchases_batch(self, user: User, items: list[ConstructionPurchaseCreate]) -> list[ConstructionPurchase]:
        return [await self._build_purchase(user, item) for item in items]

    async def update_purchase(
        self, user: User, purchase_id: uuid.UUID, payload: ConstructionPurchaseUpdate
    ) -> ConstructionPurchase:
        record = await self.get_purchase(user, purchase_id)
        ensure_version(record, payload.version)
        if payload.material_id:
            await self._require_active_material(user, payload.material_id)
        if payload.purchase_date:
            validate_business_date(payload.purchase_date, user.clinic.timezone)
        data = payload.model_dump(exclude_unset=True, exclude={"version"})
        for key, value in data.items():
            setattr(record, key, value)
        record.amount = (record.quantity * record.unit_price).quantize(TWO_PLACES, rounding=ROUND_HALF_UP)
        record.bump()
        await self.session.flush()
        return record

    async def delete_purchase(self, user: User, purchase_id: uuid.UUID, version: int) -> ConstructionPurchase:
        record = await self.get_purchase(user, purchase_id)
        ensure_version(record, version)
        record.soft_delete()
        await self.session.flush()
        return record

    async def _build_purchase(self, user: User, payload: ConstructionPurchaseCreate) -> ConstructionPurchase:
        material = await self._require_active_material(user, payload.material_id)
        validate_business_date(payload.purchase_date, user.clinic.timezone)
        if payload.id and await self.purchases.get(user.id, payload.id):
            raise ConflictError("A construction purchase with this id already exists.")
        amount = (payload.quantity * payload.unit_price).quantize(TWO_PLACES, rounding=ROUND_HALF_UP)
        record = ConstructionPurchase(
            id=payload.id or uuid.uuid4(),
            user_id=user.id,
            material_id=payload.material_id,
            purchase_date=payload.purchase_date,
            quantity=payload.quantity,
            unit=payload.unit or material.unit,
            unit_price=payload.unit_price,
            amount=amount,
            supplier=payload.supplier,
            notes=payload.notes,
        )
        return await self.purchases.add(record)

    async def _require_active_category(self, user: User, category_id: uuid.UUID) -> ConstructionMaterialCategory:
        record = await self.get_category(user, category_id)
        if not record.is_active:
            raise ConflictError("This category is inactive.")
        return record

    async def _require_active_material(self, user: User, material_id: uuid.UUID) -> ConstructionMaterial:
        record = await self.get_material(user, material_id)
        if not record.is_active:
            raise ConflictError("This material is inactive.")
        return record
