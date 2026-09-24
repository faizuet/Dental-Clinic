import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.treatment_category import TreatmentCategoryCreate, TreatmentCategoryRead, TreatmentCategoryUpdate
from app.services.treatment_service import TreatmentService
from app.utils.pagination import paginated

router = APIRouter(prefix="/treatment-categories", tags=["treatment-categories"])


@router.get("")
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
    items, total = await TreatmentService(session).list_categories(
        user,
        search=search,
        active=active,
        include_deleted=include_deleted,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [TreatmentCategoryRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=TreatmentCategoryRead)
async def create_category(payload: TreatmentCategoryCreate, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).create_category(user, payload)


@router.get("/{category_id}", response_model=TreatmentCategoryRead)
async def get_category(category_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).get_category(user, category_id)


@router.patch("/{category_id}", response_model=TreatmentCategoryRead)
async def update_category(
    category_id: uuid.UUID, payload: TreatmentCategoryUpdate, user: CurrentUser, session: DBSession
):
    return await TreatmentService(session).update_category(user, category_id, payload)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(
    category_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await TreatmentService(session).delete_category(user, category_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
