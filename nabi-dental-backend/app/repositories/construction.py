from datetime import date
from uuid import UUID

from sqlalchemy import func, or_, select

from app.models.construction import ConstructionMaterial, ConstructionMaterialCategory, ConstructionPurchase
from app.repositories.base import BaseRepository, apply_sort


class ConstructionMaterialCategoryRepository(BaseRepository):
    def _base(self, user_id: UUID, *, include_deleted: bool = False):
        stmt = select(ConstructionMaterialCategory).where(ConstructionMaterialCategory.user_id == user_id)
        if not include_deleted:
            stmt = stmt.where(ConstructionMaterialCategory.deleted_at.is_(None))
        return stmt

    async def get(self, user_id: UUID, category_id: UUID) -> ConstructionMaterialCategory | None:
        return await self.session.scalar(self._base(user_id).where(ConstructionMaterialCategory.id == category_id))

    async def list_filtered(
        self,
        user_id: UUID,
        *,
        search: str | None,
        active: bool | None,
        include_deleted: bool,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[ConstructionMaterialCategory], int]:
        stmt = self._base(user_id, include_deleted=include_deleted)
        if search:
            stmt = stmt.where(ConstructionMaterialCategory.name.ilike(f"%{search}%"))
        if active is not None:
            stmt = stmt.where(ConstructionMaterialCategory.is_active.is_(active))
        stmt = apply_sort(
            stmt,
            ConstructionMaterialCategory,
            sort,
            "display_order",
            {"display_order", "name", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total

    async def name_taken(self, user_id: UUID, name: str, *, exclude_id: UUID | None = None) -> bool:
        stmt = select(ConstructionMaterialCategory.id).where(
            ConstructionMaterialCategory.user_id == user_id,
            ConstructionMaterialCategory.deleted_at.is_(None),
            func.lower(ConstructionMaterialCategory.name) == name.lower(),
        )
        if exclude_id:
            stmt = stmt.where(ConstructionMaterialCategory.id != exclude_id)
        return await self.session.scalar(stmt) is not None

    async def next_order(self, user_id: UUID) -> int:
        return await self.max_order(
            ConstructionMaterialCategory.display_order,
            ConstructionMaterialCategory.user_id == user_id,
            ConstructionMaterialCategory.deleted_at.is_(None),
        )

    async def has_materials(self, category_id: UUID) -> bool:
        return (
            await self.session.scalar(
                select(ConstructionMaterial.id).where(ConstructionMaterial.category_id == category_id).limit(1)
            )
            is not None
        )


class ConstructionMaterialRepository(BaseRepository):
    def _base(self, user_id: UUID, *, include_deleted: bool = False):
        stmt = select(ConstructionMaterial).where(ConstructionMaterial.user_id == user_id)
        if not include_deleted:
            stmt = stmt.where(ConstructionMaterial.deleted_at.is_(None))
        return stmt

    async def get(self, user_id: UUID, material_id: UUID) -> ConstructionMaterial | None:
        return await self.session.scalar(self._base(user_id).where(ConstructionMaterial.id == material_id))

    async def list_filtered(
        self,
        user_id: UUID,
        *,
        search: str | None,
        active: bool | None,
        category_id: UUID | None,
        include_deleted: bool,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[ConstructionMaterial], int]:
        stmt = self._base(user_id, include_deleted=include_deleted)
        if search:
            stmt = stmt.where(ConstructionMaterial.name.ilike(f"%{search}%"))
        if active is not None:
            stmt = stmt.where(ConstructionMaterial.is_active.is_(active))
        if category_id:
            stmt = stmt.where(ConstructionMaterial.category_id == category_id)
        stmt = apply_sort(
            stmt,
            ConstructionMaterial,
            sort,
            "display_order",
            {"display_order", "name", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total

    async def name_taken(self, user_id: UUID, name: str, *, exclude_id: UUID | None = None) -> bool:
        stmt = select(ConstructionMaterial.id).where(
            ConstructionMaterial.user_id == user_id,
            ConstructionMaterial.deleted_at.is_(None),
            func.lower(ConstructionMaterial.name) == name.lower(),
        )
        if exclude_id:
            stmt = stmt.where(ConstructionMaterial.id != exclude_id)
        return await self.session.scalar(stmt) is not None

    async def next_order(self, user_id: UUID) -> int:
        return await self.max_order(
            ConstructionMaterial.display_order,
            ConstructionMaterial.user_id == user_id,
            ConstructionMaterial.deleted_at.is_(None),
        )

    async def has_purchases(self, material_id: UUID) -> bool:
        return (
            await self.session.scalar(
                select(ConstructionPurchase.id).where(ConstructionPurchase.material_id == material_id).limit(1)
            )
            is not None
        )


class ConstructionPurchaseRepository(BaseRepository):
    def _base(self, user_id: UUID, *, include_deleted: bool = False):
        stmt = select(ConstructionPurchase).where(ConstructionPurchase.user_id == user_id)
        if not include_deleted:
            stmt = stmt.where(ConstructionPurchase.deleted_at.is_(None))
        return stmt

    async def get(self, user_id: UUID, purchase_id: UUID) -> ConstructionPurchase | None:
        return await self.session.scalar(
            self._base(user_id, include_deleted=True).where(ConstructionPurchase.id == purchase_id)
        )

    async def list_filtered(
        self,
        user_id: UUID,
        *,
        from_date: date | None,
        to_date: date | None,
        material_id: UUID | None,
        search: str | None,
        page: int,
        page_size: int,
        sort: str | None,
    ) -> tuple[list[ConstructionPurchase], int]:
        stmt = self._base(user_id)
        if from_date:
            stmt = stmt.where(ConstructionPurchase.purchase_date >= from_date)
        if to_date:
            stmt = stmt.where(ConstructionPurchase.purchase_date <= to_date)
        if material_id:
            stmt = stmt.where(ConstructionPurchase.material_id == material_id)
        if search:
            pattern = f"%{search}%"
            stmt = stmt.join(ConstructionMaterial, ConstructionMaterial.id == ConstructionPurchase.material_id).where(
                or_(
                    ConstructionPurchase.notes.ilike(pattern),
                    ConstructionPurchase.supplier.ilike(pattern),
                    ConstructionMaterial.name.ilike(pattern),
                )
            )
        stmt = apply_sort(
            stmt,
            ConstructionPurchase,
            sort,
            "-purchase_date",
            {"purchase_date", "amount", "created_at"},
        )
        items, total = await self.paginate(stmt, page=page, page_size=page_size)
        return list(items), total
