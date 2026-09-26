import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.home_budget import HomeBudgetCreate, HomeBudgetCurrent, HomeBudgetRead, HomeBudgetUpdate
from app.services.home_expense_service import HomeExpenseService
from app.utils.dates import today_in_timezone
from app.utils.pagination import paginated

router = APIRouter(prefix="/home-budgets", tags=["home-budgets"])


@router.get("")
async def list_budgets(
    user: CurrentUser,
    session: DBSession,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
):
    items, total = await HomeExpenseService(session).list_budgets(user, page=page, page_size=page_size)
    return paginated(
        [HomeBudgetRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.get("/current", response_model=HomeBudgetCurrent)
async def current_budget(
    user: CurrentUser,
    session: DBSession,
    year: int | None = None,
    month: int | None = None,
):
    today = today_in_timezone(user.clinic.timezone)
    return await HomeExpenseService(session).current_budget(user, year or today.year, month or today.month)


@router.put("/current", response_model=HomeBudgetRead)
async def upsert_current_budget(payload: HomeBudgetCreate, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).upsert_month_budget(user, payload)


@router.post("", status_code=status.HTTP_201_CREATED, response_model=HomeBudgetRead)
async def create_budget(payload: HomeBudgetCreate, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).create_budget(user, payload)


@router.get("/{budget_id}", response_model=HomeBudgetRead)
async def get_budget(budget_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).get_budget(user, budget_id)


@router.patch("/{budget_id}", response_model=HomeBudgetRead)
async def update_budget(budget_id: uuid.UUID, payload: HomeBudgetUpdate, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).update_budget(user, budget_id, payload)


@router.delete("/{budget_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_budget(
    budget_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await HomeExpenseService(session).delete_budget(user, budget_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
