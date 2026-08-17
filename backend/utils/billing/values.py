from decimal import Decimal
from typing import Any, Mapping


_ZERO_DECIMAL_CURRENCIES = {
    'BIF',
    'CLP',
    'DJF',
    'GNF',
    'JPY',
    'KMF',
    'KRW',
    'PYG',
    'RWF',
    'UGX',
    'VND',
    'VUV',
    'XAF',
    'XOF',
    'XPF',
}
_THREE_DECIMAL_CURRENCIES = {'BHD', 'IQD', 'JOD', 'KWD', 'OMR', 'TND'}


def as_mapping(value: Any, *, label: str = 'billing value') -> Mapping[str, Any]:
    if isinstance(value, Mapping):
        return value
    dump = getattr(value, 'model_dump', None)
    if callable(dump):
        result = dump(mode='json')
        if isinstance(result, Mapping):
            return result
    raise TypeError(f'{label} must be a mapping')


def format_recurring_price(amount_minor: Any, currency: Any, interval: Any) -> str:
    if not isinstance(amount_minor, int) or isinstance(amount_minor, bool) or amount_minor < 0:
        raise ValueError('billing price must be a non-negative integer in minor units')
    if not isinstance(currency, str) or len(currency) != 3:
        raise ValueError('billing price must include an ISO currency')
    normalized_currency = currency.upper()
    normalized_interval = str(interval).lower()
    if normalized_interval not in {'month', 'year'}:
        raise ValueError('billing price interval must be month or year')
    exponent = (
        0
        if normalized_currency in _ZERO_DECIMAL_CURRENCIES
        else 3 if normalized_currency in _THREE_DECIMAL_CURRENCIES else 2
    )
    amount = Decimal(amount_minor).scaleb(-exponent)
    return f'{normalized_currency} {amount:.{exponent}f}/{normalized_interval}'
