from datetime import date

from fastapi import APIRouter
from fastapi.responses import Response

from app.api.deps import CurrentUser, DBSession
from app.core.constants import ExportFormat, GroupBy
from app.schemas.report import ClinicReport, HomeReport
from app.services.report_service import ReportService
from app.utils.dates import today_in_timezone, year_bounds

router = APIRouter(prefix="/reports", tags=["reports"])


def _range(user, from_date: date | None, to_date: date | None) -> tuple[date, date]:
    if from_date is None or to_date is None:
        today = today_in_timezone(user.clinic.timezone)
        return year_bounds(today.year) if from_date is None and to_date is None else (
            from_date or to_date,
            to_date or from_date,
        )
    return from_date, to_date


@router.get("/clinic", response_model=ClinicReport)
async def clinic_report(
    user: CurrentUser,
    session: DBSession,
    from_date: date | None = None,
    to_date: date | None = None,
    group_by: GroupBy = GroupBy.DAY,
):
    start, end = _range(user, from_date, to_date)
    return await ReportService(session).clinic_report(user, from_date=start, to_date=end, group_by=group_by)


@router.get("/home", response_model=HomeReport)
async def home_report(
    user: CurrentUser,
    session: DBSession,
    from_date: date | None = None,
    to_date: date | None = None,
    group_by: GroupBy = GroupBy.DAY,
):
    start, end = _range(user, from_date, to_date)
    return await ReportService(session).home_report(user, from_date=start, to_date=end, group_by=group_by)


@router.get("/clinic/export")
async def export_clinic_report(
    user: CurrentUser,
    session: DBSession,
    from_date: date | None = None,
    to_date: date | None = None,
    group_by: GroupBy = GroupBy.DAY,
    format: ExportFormat = ExportFormat.PDF,
):
    start, end = _range(user, from_date, to_date)
    content, filename, media_type = await ReportService(session).export_clinic(
        user, from_date=start, to_date=end, group_by=group_by, fmt=format
    )
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/home/export")
async def export_home_report(
    user: CurrentUser,
    session: DBSession,
    from_date: date | None = None,
    to_date: date | None = None,
    group_by: GroupBy = GroupBy.DAY,
    format: ExportFormat = ExportFormat.PDF,
):
    start, end = _range(user, from_date, to_date)
    content, filename, media_type = await ReportService(session).export_home(
        user, from_date=start, to_date=end, group_by=group_by, fmt=format
    )
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
