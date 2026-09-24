from datetime import date

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, DBSession
from app.core.constants import Period
from app.schemas.dashboard import ClinicDashboard, HomeDashboard
from app.services.dashboard_service import DashboardService

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/clinic", response_model=ClinicDashboard)
async def clinic_dashboard(
    user: CurrentUser,
    session: DBSession,
    period: Period = Period.DAILY,
    date: date | None = None,
    from_date: date | None = None,
    to_date: date | None = None,
):
    return await DashboardService(session).clinic(
        user,
        period=period,
        value_date=date,
        from_date=from_date,
        to_date=to_date,
    )


@router.get("/home", response_model=HomeDashboard)
async def home_dashboard(
    user: CurrentUser,
    session: DBSession,
    period: Period = Period.DAILY,
    date: date | None = None,
    from_date: date | None = None,
    to_date: date | None = None,
):
    return await DashboardService(session).home(
        user,
        period=period,
        value_date=date,
        from_date=from_date,
        to_date=to_date,
    )
