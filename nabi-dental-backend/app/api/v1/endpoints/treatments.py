import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.treatment import TreatmentCreate, TreatmentRead, TreatmentUpdate
from app.services.treatment_service import TreatmentService
from app.utils.pagination import paginated

router = APIRouter(prefix="/treatments", tags=["treatments"])


@router.get("")
async def list_treatments(
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
    items, total = await TreatmentService(session).list_treatments(
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
        [TreatmentRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=TreatmentRead)
async def create_treatment(payload: TreatmentCreate, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).create_treatment(user, payload)


@router.get("/{treatment_id}", response_model=TreatmentRead)
async def get_treatment(treatment_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).get_treatment(user, treatment_id)


@router.patch("/{treatment_id}", response_model=TreatmentRead)
async def update_treatment(treatment_id: uuid.UUID, payload: TreatmentUpdate, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).update_treatment(user, treatment_id, payload)


@router.delete("/{treatment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_treatment(
    treatment_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await TreatmentService(session).delete_treatment(user, treatment_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
