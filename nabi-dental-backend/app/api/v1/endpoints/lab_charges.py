import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.lab_charge import LabChargeCreate, LabChargeRead, LabChargeUpdate
from app.services.lab_charge_service import LabChargeService
from app.utils.pagination import paginated

router = APIRouter(prefix="/lab-charges", tags=["lab-charges"])


@router.get("")
async def list_lab_charges(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    from_date: date | None = None,
    to_date: date | None = None,
    patient_id: uuid.UUID | None = None,
    transaction_id: uuid.UUID | None = None,
    search: str | None = None,
    sort: str | None = None,
):
    items, total = await LabChargeService(session).list_charges(
        user,
        from_date=from_date,
        to_date=to_date,
        patient_id=patient_id,
        transaction_id=transaction_id,
        search=search,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [LabChargeRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=LabChargeRead)
async def create_lab_charge(payload: LabChargeCreate, user: CurrentUser, session: DBSession):
    return await LabChargeService(session).create_charge(user, payload)


@router.get("/{charge_id}", response_model=LabChargeRead)
async def get_lab_charge(charge_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await LabChargeService(session).get_charge(user, charge_id)


@router.patch("/{charge_id}", response_model=LabChargeRead)
async def update_lab_charge(charge_id: uuid.UUID, payload: LabChargeUpdate, user: CurrentUser, session: DBSession):
    return await LabChargeService(session).update_charge(user, charge_id, payload)


@router.delete("/{charge_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_lab_charge(
    charge_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await LabChargeService(session).delete_charge(user, charge_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
