import pytest

from app.utils.phone import normalize_optional_phone


@pytest.mark.parametrize(
    "value",
    ["03001234567", "03123456789", "03999999999"],
)
def test_valid_pakistani_mobiles(value):
    assert normalize_optional_phone(value) == value


@pytest.mark.parametrize(
    "value",
    [
        "0300123456",
        "030012345678",
        "923001234567",
        "0300ABC4567",
        "0300 1234567",
        "0300-1234567",
        "+923001234567",
        "12345678901",
    ],
)
def test_invalid_pakistani_mobiles(value):
    with pytest.raises(ValueError, match="11-digit Pakistani mobile"):
        normalize_optional_phone(value)


def test_blank_phone_is_optional():
    assert normalize_optional_phone(None) is None
    assert normalize_optional_phone("  ") is None
