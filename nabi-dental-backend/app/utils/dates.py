from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.core.config import settings
from app.core.exceptions import ValidationAppError


def parse_timezone(name: str) -> ZoneInfo:
    try:
        return ZoneInfo(name)
    except ZoneInfoNotFoundError as exc:
        raise ValidationAppError(
            "Timezone is not a valid IANA timezone.",
            details=[{"field": "timezone", "message": "Timezone is not a valid IANA timezone."}],
        ) from exc


def today_in_timezone(tz_name: str) -> date:
    return datetime.now(parse_timezone(tz_name)).date()


def add_years(value: date, years: int) -> date:
    try:
        return value.replace(year=value.year + years)
    except ValueError:
        return value.replace(year=value.year + years, month=2, day=28)


def month_bounds(year: int, month: int) -> tuple[date, date]:
    start = date(year, month, 1)
    if month == 12:
        end = date(year, 12, 31)
    else:
        end = date(year, month + 1, 1) - timedelta(days=1)
    return start, end


def year_bounds(year: int) -> tuple[date, date]:
    return date(year, 1, 1), date(year, 12, 31)


def resolve_period_range(
    *,
    period: str,
    value_date: date | None,
    from_date: date | None,
    to_date: date | None,
    tz_name: str,
) -> tuple[date, date]:
    today = today_in_timezone(tz_name)
    anchor = value_date or today

    if period == "daily":
        return anchor, anchor
    if period == "monthly":
        return month_bounds(anchor.year, anchor.month)
    if period == "yearly":
        return year_bounds(anchor.year)
    if period == "custom":
        if from_date is None or to_date is None:
            raise ValidationAppError(
                "Custom ranges require from_date and to_date.",
                details=[
                    {"field": "from_date", "message": "from_date and to_date are required for a custom range."}
                ],
            )
        validate_inclusive_range(from_date, to_date)
        return from_date, to_date
    raise ValidationAppError(
        "Period is invalid.",
        details=[{"field": "period", "message": "Period must be daily, monthly, yearly, or custom."}],
    )


def validate_inclusive_range(from_date: date, to_date: date) -> None:
    if from_date > to_date:
        raise ValidationAppError(
            "from_date must be on or before to_date.",
            details=[{"field": "from_date", "message": "from_date must be on or before to_date."}],
        )
    if to_date > add_years(from_date, settings.MAX_RANGE_YEARS):
        raise ValidationAppError(
            "The selected range cannot exceed 10 years.",
            details=[{"field": "to_date", "message": "The selected range cannot exceed 10 years."}],
        )


def validate_business_date(value: date, tz_name: str) -> None:
    limit = today_in_timezone(tz_name) + timedelta(days=settings.MAX_FUTURE_DAYS)
    if value > limit:
        raise ValidationAppError(
            "The date cannot be more than 30 days in the future.",
            details=[{"field": "date", "message": f"Dates may be at most {settings.MAX_FUTURE_DAYS} days in the future."}],
        )


def format_display_date(value: date | datetime | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        value = value.date()
    if isinstance(value, date):
        return value.strftime("%d/%m/%y")
    text = str(value).strip()
    if not text:
        return ""
    if len(text) >= 10 and text[4] == "-" and text[7] == "-":
        try:
            return date.fromisoformat(text[:10]).strftime("%d/%m/%y")
        except ValueError:
            return text
    return text


def format_display_date_range(from_date, to_date, *, separator: str = " to ") -> str:
    return f"{format_display_date(from_date)}{separator}{format_display_date(to_date)}"


def serialize_datetime(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
