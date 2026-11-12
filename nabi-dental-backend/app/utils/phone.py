import re

PAKISTANI_MOBILE_PATTERN = re.compile(r"^03\d{9}$")
PAKISTANI_MOBILE_MESSAGE = "Enter an 11-digit Pakistani mobile number starting with 03."


def normalize_optional_phone(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    if not PAKISTANI_MOBILE_PATTERN.fullmatch(cleaned):
        raise ValueError(PAKISTANI_MOBILE_MESSAGE)
    return cleaned
