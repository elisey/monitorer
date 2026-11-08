import pytest

from ddc_probe import check_writable
from ddc_probe.ddc import DDCError


@pytest.mark.parametrize("value", [0x01, 0x02, 0x04, 0x08, 0x21, 0x22])
def test_declared_picture_format_values_are_writable(value):
    check_writable(0x86, value)


def test_undeclared_value_is_rejected():
    with pytest.raises(DDCError, match="not allowed for VCP 0x86"):
        check_writable(0x86, 0x03)


def test_other_codes_are_rejected():
    with pytest.raises(DDCError, match="writing VCP 0x04 is not allowed"):
        check_writable(0x04, 0x01)
