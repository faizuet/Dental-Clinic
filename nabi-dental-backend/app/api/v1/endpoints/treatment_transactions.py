import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.treatment_transaction import (
    TreatmentTransactionBatchCreate,
    TreatmentTransactionCreate,
    TreatmentTransactionRead,
    TreatmentTransactionUpdate,
)
from app.services.treatment_service import TreatmentService
from app.utils.pagination import paginated

router = APIRouter(prefix="/treatment-transactions", tags=["treatment-transactions"])


@router.get("")
async def list_transactions(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    from_date: date | None = None,
    to_date: date | None = None,
    treatment_id: uuid.UUID | None = None,
    category_id: uuid.UUID | None = None,
    search: str | None = None,
    sort: str | None = None,
):
    items, total = await TreatmentService(session).list_transactions(
        user,
        from_date=from_date,
        to_date=to_date,
        treatment_id=treatment_id,
        category_id=category_id,
        search=search,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [TreatmentTransactionRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=TreatmentTransactionRead)
async def create_transaction(payload: TreatmentTransactionCreate, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).create_transaction(user, payload)


@router.post("/batch", status_code=status.HTTP_201_CREATED)
async def create_transactions_batch(payload: TreatmentTransactionBatchCreate, user: CurrentUser, session: DBSession):
    items = await TreatmentService(session).create_transactions_batch(user, payload.items)
    return [TreatmentTransactionRead.model_validate(item) for item in items]


@router.get("/{transaction_id}", response_model=TreatmentTransactionRead)
async def get_transaction(transaction_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await TreatmentService(session).get_transaction(user, transaction_id)


@router.patch("/{transaction_id}", response_model=TreatmentTransactionRead)
async def update_transaction(
    transaction_id: uuid.UUID, payload: TreatmentTransactionUpdate, user: CurrentUser, session: DBSession
):
    return await TreatmentService(session).update_transaction(user, transaction_id, payload)


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(
    transaction_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await TreatmentService(session).delete_transaction(user, transaction_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
