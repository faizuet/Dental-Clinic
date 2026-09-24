import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.construction import (
    ConstructionMaterialCategoryCreate,
    ConstructionMaterialCategoryRead,
    ConstructionMaterialCategoryUpdate,
    ConstructionMaterialCreate,
    ConstructionMaterialRead,
    ConstructionMaterialUpdate,
    ConstructionPurchaseBatchCreate,
    ConstructionPurchaseCreate,
    ConstructionPurchaseRead,
    ConstructionPurchaseUpdate,
)
from app.services.construction_service import ConstructionService
from app.utils.pagination import paginated

categories_router = APIRouter(prefix="/construction-material-categories", tags=["construction"])
materials_router = APIRouter(prefix="/construction-materials", tags=["construction"])
purchases_router = APIRouter(prefix="/construction-purchases", tags=["construction"])


@categories_router.get("")
async def list_categories(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    search: str | None = None,
    active: bool | None = None,
    include_deleted: bool = False,
    sort: str | None = None,
):
    items, total = await ConstructionService(session).list_categories(
        user,
        search=search,
        active=active,
        include_deleted=include_deleted,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [ConstructionMaterialCategoryRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@categories_router.post("", status_code=status.HTTP_201_CREATED, response_model=ConstructionMaterialCategoryRead)
async def create_category(payload: ConstructionMaterialCategoryCreate, user: CurrentUser, session: DBSession):
    return await ConstructionService(session).create_category(user, payload)


@categories_router.get("/{category_id}", response_model=ConstructionMaterialCategoryRead)
async def get_category(category_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await ConstructionService(session).get_category(user, category_id)


@categories_router.patch("/{category_id}", response_model=ConstructionMaterialCategoryRead)
async def update_category(
    category_id: uuid.UUID, payload: ConstructionMaterialCategoryUpdate, user: CurrentUser, session: DBSession
):
    return await ConstructionService(session).update_category(user, category_id, payload)


@categories_router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(
    category_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await ConstructionService(session).delete_category(user, category_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@materials_router.get("")
async def list_materials(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    search: str | None = None,
    active: bool | None = None,
    category_id: uuid.UUID | None = None,
    include_deleted: bool = False,
    sort: str | None = None,
):
    items, total = await ConstructionService(session).list_materials(
        user,
        search=search,
        active=active,
        category_id=category_id,
        include_deleted=include_deleted,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [ConstructionMaterialRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@materials_router.post("", status_code=status.HTTP_201_CREATED, response_model=ConstructionMaterialRead)
async def create_material(payload: ConstructionMaterialCreate, user: CurrentUser, session: DBSession):
    return await ConstructionService(session).create_material(user, payload)


@materials_router.get("/{material_id}", response_model=ConstructionMaterialRead)
async def get_material(material_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await ConstructionService(session).get_material(user, material_id)


@materials_router.patch("/{material_id}", response_model=ConstructionMaterialRead)
async def update_material(
    material_id: uuid.UUID, payload: ConstructionMaterialUpdate, user: CurrentUser, session: DBSession
):
    return await ConstructionService(session).update_material(user, material_id, payload)


@materials_router.delete("/{material_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_material(
    material_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await ConstructionService(session).delete_material(user, material_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@purchases_router.get("")
async def list_purchases(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    from_date: date | None = None,
    to_date: date | None = None,
    material_id: uuid.UUID | None = None,
    search: str | None = None,
    sort: str | None = None,
):
    items, total = await ConstructionService(session).list_purchases(
        user,
        from_date=from_date,
        to_date=to_date,
        material_id=material_id,
        search=search,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [ConstructionPurchaseRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@purchases_router.post("", status_code=status.HTTP_201_CREATED, response_model=ConstructionPurchaseRead)
async def create_purchase(payload: ConstructionPurchaseCreate, user: CurrentUser, session: DBSession):
    return await ConstructionService(session).create_purchase(user, payload)


@purchases_router.post("/batch", status_code=status.HTTP_201_CREATED)
async def create_purchases_batch(payload: ConstructionPurchaseBatchCreate, user: CurrentUser, session: DBSession):
    items = await ConstructionService(session).create_purchases_batch(user, payload.items)
    return [ConstructionPurchaseRead.model_validate(item) for item in items]


@purchases_router.get("/{purchase_id}", response_model=ConstructionPurchaseRead)
async def get_purchase(purchase_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await ConstructionService(session).get_purchase(user, purchase_id)


@purchases_router.patch("/{purchase_id}", response_model=ConstructionPurchaseRead)
async def update_purchase(
    purchase_id: uuid.UUID, payload: ConstructionPurchaseUpdate, user: CurrentUser, session: DBSession
):
    return await ConstructionService(session).update_purchase(user, purchase_id, payload)


@purchases_router.delete("/{purchase_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_purchase(
    purchase_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await ConstructionService(session).delete_purchase(user, purchase_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
