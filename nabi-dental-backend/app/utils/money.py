from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Annotated, Any

from pydantic import BeforeValidator, PlainSerializer

MAX_MONEY = Decimal("999999999999.99")
TWO_PLACES = Decimal("0.01")


def parse_money(value: Any) -> Decimal:
    if isinstance(value, Decimal):
        amount = value
    else:
        try:
            amount = Decimal(str(value))
        except (InvalidOperation, TypeError, ValueError) as exc:
            raise ValueError("Invalid monetary value.") from exc
    if amount.copy_abs() > MAX_MONEY:
        raise ValueError("Amount exceeds the maximum allowed value.")
    if amount.as_tuple().exponent < -2:
        raise ValueError("Amount must have at most two decimal places.")
    return amount.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


def require_positive_money(value: Any) -> Decimal:
    amount = parse_money(value)
    if amount <= 0:
        raise ValueError("Amount must be greater than zero.")
    return amount


def require_non_negative_money(value: Any) -> Decimal:
    amount = parse_money(value)
    if amount < 0:
        raise ValueError("Amount must be greater than or equal to zero.")
    return amount


def format_money(value: Decimal) -> str:
    return f"{value.quantize(TWO_PLACES, rounding=ROUND_HALF_UP):.2f}"


THREE_PLACES = Decimal("0.001")
MAX_QUANTITY = Decimal("999999999.999")


def parse_quantity(value: Any) -> Decimal:
    if isinstance(value, Decimal):
        amount = value
    else:
        try:
            amount = Decimal(str(value))
        except (InvalidOperation, TypeError, ValueError) as exc:
            raise ValueError("Invalid quantity.") from exc
    if amount.copy_abs() > MAX_QUANTITY:
        raise ValueError("Quantity exceeds the maximum allowed value.")
    if amount.as_tuple().exponent < -3:
        raise ValueError("Quantity must have at most three decimal places.")
    return amount.quantize(THREE_PLACES, rounding=ROUND_HALF_UP)


def require_positive_quantity(value: Any) -> Decimal:
    amount = parse_quantity(value)
    if amount <= 0:
        raise ValueError("Quantity must be greater than zero.")
    return amount


def format_quantity(value: Decimal) -> str:
    text = f"{value.quantize(THREE_PLACES, rounding=ROUND_HALF_UP):.3f}"
    return text.rstrip("0").rstrip(".") if "." in text else text


QuantityPositive = Annotated[
    Decimal,
    BeforeValidator(require_positive_quantity),
    PlainSerializer(format_quantity, return_type=str),
]


MoneyPositive = Annotated[
    Decimal,
    BeforeValidator(require_positive_money),
    PlainSerializer(format_money, return_type=str),
]

MoneyNonNegative = Annotated[
    Decimal,
    BeforeValidator(require_non_negative_money),
    PlainSerializer(format_money, return_type=str),
]

MoneyOptionalPositive = Annotated[
    Decimal | None,
    BeforeValidator(lambda v: None if v is None else require_positive_money(v)),
    PlainSerializer(lambda v: format_money(v) if v is not None else None, return_type=str | None),
]
