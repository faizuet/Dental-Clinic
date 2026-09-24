import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.home_expense import HomeExpenseBatchCreate, HomeExpenseCreate, HomeExpenseRead, HomeExpenseUpdate
from app.services.home_expense_service import HomeExpenseService
from app.utils.pagination import paginated

router = APIRouter(prefix="/home-expenses", tags=["home-expenses"])


@router.get("")
async def list_expenses(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    from_date: date | None = None,
    to_date: date | None = None,
    category_id: uuid.UUID | None = None,
    search: str | None = None,
    sort: str | None = None,
):
    items, total = await HomeExpenseService(session).list_expenses(
        user,
        from_date=from_date,
        to_date=to_date,
        category_id=category_id,
        search=search,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [HomeExpenseRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=HomeExpenseRead)
async def create_expense(payload: HomeExpenseCreate, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).create_expense(user, payload)


@router.post("/batch", status_code=status.HTTP_201_CREATED)
async def create_expenses_batch(payload: HomeExpenseBatchCreate, user: CurrentUser, session: DBSession):
    items = await HomeExpenseService(session).create_expenses_batch(user, payload.items)
    return [HomeExpenseRead.model_validate(item) for item in items]


@router.get("/{expense_id}", response_model=HomeExpenseRead)
async def get_expense(expense_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).get_expense(user, expense_id)


@router.patch("/{expense_id}", response_model=HomeExpenseRead)
async def update_expense(expense_id: uuid.UUID, payload: HomeExpenseUpdate, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).update_expense(user, expense_id, payload)


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_expense(
    expense_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await HomeExpenseService(session).delete_expense(user, expense_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
