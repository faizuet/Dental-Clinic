from decimal import Decimal

from app.utils.money import require_positive_money, require_non_negative_money


def test_money_rejects_too_many_decimals():
    try:
        require_positive_money("1.001")
        assert False
    except ValueError:
        pass


def test_money_formats_two_places():
    assert str(require_positive_money("5000")) == "5000.00"
    assert require_non_negative_money("0") == Decimal("0.00")
