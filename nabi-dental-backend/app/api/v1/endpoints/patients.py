import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.patient import PatientCreate, PatientRead, PatientUpdate
from app.services.treatment_service import TreatmentService
from app.utils.pagination import paginated

router = APIRouter(prefix="/patients", tags=["patients"])


@router.get("")
async def list_patients(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    search: str | None = None,
    sort: str | None = None,
):
    items, total = await TreatmentService(session).list_patients(
        user,
        search=search,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [PatientRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=PatientRead)
async def create_patient(payload: PatientCreate, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).create_patient(user, payload)


@router.get("/{patient_id}", response_model=PatientRead)
async def get_patient(patient_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).get_patient(user, patient_id)


@router.get("/{patient_id}/treatments")
async def list_patient_treatments(
    patient_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
):
    service = TreatmentService(session)
    await service.get_patient(user, patient_id)
    items, total = await service.list_transactions(
        user,
        from_date=None,
        to_date=None,
        treatment_id=None,
        category_id=None,
        search=None,
        page=page,
        page_size=page_size,
        sort="-transaction_date",
        patient_id=patient_id,
    )
    return paginated(
        [service.serialize_transaction(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.patch("/{patient_id}", response_model=PatientRead)
async def update_patient(patient_id: uuid.UUID, payload: PatientUpdate, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).update_patient(user, patient_id, payload)


@router.delete("/{patient_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_patient(
    patient_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await TreatmentService(session).delete_patient(user, patient_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
