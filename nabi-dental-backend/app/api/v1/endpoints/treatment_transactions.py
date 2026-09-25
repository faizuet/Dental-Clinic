import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, File, Form, Query, Response, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import CurrentUser, DBSession
from app.schemas.treatment_transaction import (
    TreatmentAttachmentRead,
    TreatmentTransactionBatchCreate,
    TreatmentTransactionCreate,
    TreatmentTransactionRead,
    TreatmentTransactionUpdate,
)
from app.services.report_service import ReportService
from app.services.treatment_service import TreatmentService
from app.services.xray_service import XrayService
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
    patient_id: uuid.UUID | None = None,
    search: str | None = None,
    sort: str | None = None,
):
    service = TreatmentService(session)
    items, total = await service.list_transactions(
        user,
        from_date=from_date,
        to_date=to_date,
        treatment_id=treatment_id,
        category_id=category_id,
        patient_id=patient_id,
        search=search,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [service.serialize_transaction(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=TreatmentTransactionRead)
async def create_transaction(payload: TreatmentTransactionCreate, user: CurrentUser, session: DBSession):
    service = TreatmentService(session)
    record = await service.create_transaction(user, payload)
    return service.serialize_transaction(record)


@router.post("/batch", status_code=status.HTTP_201_CREATED)
async def create_transactions_batch(payload: TreatmentTransactionBatchCreate, user: CurrentUser, session: DBSession):
    service = TreatmentService(session)
    items = await service.create_transactions_batch(user, payload.items)
    return [service.serialize_transaction(item) for item in items]


@router.get("/{transaction_id}", response_model=TreatmentTransactionRead)
async def get_transaction(transaction_id: uuid.UUID, user: CurrentUser, session: DBSession):
    service = TreatmentService(session)
    return service.serialize_transaction(await service.get_transaction(user, transaction_id))


@router.get("/{transaction_id}/export")
async def export_transaction(transaction_id: uuid.UUID, user: CurrentUser, session: DBSession):
    content, filename = await ReportService(session).export_treatment(user, transaction_id)
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/{transaction_id}/attachments", status_code=status.HTTP_201_CREATED, response_model=TreatmentAttachmentRead)
async def upload_attachment(
    transaction_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    file: UploadFile = File(...),
    label: str = Form("other"),
):
    service = TreatmentService(session)
    record = await service.get_transaction(user, transaction_id)
    return await XrayService(session).save(user, record, file, label=label)


@router.get("/{transaction_id}/attachments/{attachment_id}/file")
async def get_attachment_file(
    transaction_id: uuid.UUID,
    attachment_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
):
    service = TreatmentService(session)
    await service.get_transaction(user, transaction_id)
    attachment = await service.get_attachment(user, attachment_id)
    if attachment.transaction_id != transaction_id:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("X-ray was not found.")
    path = XrayService(session).path_for(user, attachment)
    return FileResponse(path, media_type=attachment.content_type or "image/jpeg")


@router.delete("/{transaction_id}/attachments/{attachment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_attachment(
    transaction_id: uuid.UUID,
    attachment_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
):
    service = TreatmentService(session)
    await service.get_transaction(user, transaction_id)
    attachment = await service.get_attachment(user, attachment_id)
    if attachment.transaction_id != transaction_id:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("X-ray was not found.")
    await XrayService(session).delete(user, attachment)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/{transaction_id}", response_model=TreatmentTransactionRead)
async def update_transaction(
    transaction_id: uuid.UUID, payload: TreatmentTransactionUpdate, user: CurrentUser, session: DBSession
):
    service = TreatmentService(session)
    record = await service.update_transaction(user, transaction_id, payload)
    return service.serialize_transaction(record)


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(
    transaction_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await TreatmentService(session).delete_transaction(user, transaction_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
