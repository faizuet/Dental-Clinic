import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.home_expense_category import (
    HomeExpenseCategoryCreate,
    HomeExpenseCategoryRead,
    HomeExpenseCategoryUpdate,
)
from app.services.home_expense_service import HomeExpenseService
from app.utils.pagination import paginated

router = APIRouter(prefix="/home-expense-categories", tags=["home-expense-categories"])


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
    items, total = await HomeExpenseService(session).list_categories(
        user,
        search=search,
        active=active,
        include_deleted=include_deleted,
        page=page,
        page_size=page_size,
        sort=sort,
    )
    return paginated(
        [HomeExpenseCategoryRead.model_validate(item).model_dump(mode="json") for item in items],
        page=page,
        page_size=page_size,
        total=total,
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=HomeExpenseCategoryRead)
async def create_category(payload: HomeExpenseCategoryCreate, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).create_category(user, payload)


@router.get("/{category_id}", response_model=HomeExpenseCategoryRead)
async def get_category(category_id: uuid.UUID, user: CurrentUser, session: DBSession):
    return await HomeExpenseService(session).get_category(user, category_id)


@router.patch("/{category_id}", response_model=HomeExpenseCategoryRead)
async def update_category(
    category_id: uuid.UUID, payload: HomeExpenseCategoryUpdate, user: CurrentUser, session: DBSession
):
    return await HomeExpenseService(session).update_category(user, category_id, payload)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(
    category_id: uuid.UUID,
    user: CurrentUser,
    session: DBSession,
    version: Annotated[int, Query(ge=1)],
):
    await HomeExpenseService(session).delete_category(user, category_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
