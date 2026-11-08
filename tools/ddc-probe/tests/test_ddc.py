import pytest

from ddc_probe.ddc import (
    DDCClient,
    DDCError,
    build_capabilities_request,
    build_get_vcp_request,
    build_set_vcp_request,
    extract_reply_body,
    parse_get_vcp_reply,
    xor_checksum,
)


def make_reply(body: bytes) -> bytes:
    packet = bytes([0x6E, 0x80 | len(body)]) + body
    return packet + bytes([xor_checksum(0x50, packet)])


def vcp_reply(code: int, current: int, maximum: int = 100, result: int = 0) -> bytes:
    body = bytes(
        [0x02, result, code, 0x00, maximum >> 8, maximum & 0xFF, current >> 8, current & 0xFF]
    )
    return make_reply(body)


class FakeDisplay:
    """Emulates a display answering Get VCP, Set VCP and capabilities requests."""

    def __init__(
        self,
        values: dict[int, int],
        capabilities: bytes = b"",
        corrupt_reads: int = 0,
        ignore_sets: bool = False,
    ):
        self.values = values
        self.capabilities = capabilities
        self.corrupt_reads = corrupt_reads
        self.ignore_sets = ignore_sets
        self.pending: bytes = b""
        self.writes: list[tuple[int, int, bytes]] = []

    def write(self, chip_address: int, data_address: int, payload: bytes) -> None:
        self.writes.append((chip_address, data_address, payload))
        opcode = payload[1]
        if opcode == 0x01:
            code = payload[2]
            if code in self.values:
                self.pending = vcp_reply(code, self.values[code])
            else:
                self.pending = vcp_reply(code, 0, maximum=0, result=1)
        elif opcode == 0x03:
            if not self.ignore_sets:
                self.values[payload[2]] = (payload[3] << 8) | payload[4]
        elif opcode == 0xF3:
            offset = (payload[2] << 8) | payload[3]
            chunk = self.capabilities[offset : offset + 32]
            self.pending = make_reply(bytes([0xE3, payload[2], payload[3]]) + chunk)

    def read(self, chip_address: int, offset: int, length: int) -> bytes:
        reply = self.pending.ljust(length, b"\x00")[:length]
        if self.corrupt_reads:
            self.corrupt_reads -= 1
            corrupted = bytearray(reply)
            corrupted[2] ^= 0xFF
            return bytes(corrupted)
        return reply


def client(display: FakeDisplay) -> DDCClient:
    return DDCClient(display, sleep=lambda _: None)


def test_get_vcp_request_matches_known_luminance_packet():
    # Packet used by m1ddc and MonitorControl to read luminance (VCP 0x10).
    assert build_get_vcp_request(0x10) == bytes([0x82, 0x01, 0x10, 0xAC])


def test_capabilities_request_encodes_offset():
    request = build_capabilities_request(0x0120)
    assert request[:4] == bytes([0x83, 0xF3, 0x01, 0x20])
    assert request[4] == xor_checksum(0x6E ^ 0x51, request[:4])


def test_parse_supported_value():
    value = parse_get_vcp_reply(0x10, vcp_reply(0x10, current=85, maximum=100))
    assert value.supported
    assert value.current == 85
    assert value.maximum == 100


def test_parse_unsupported_value():
    value = parse_get_vcp_reply(0x86, vcp_reply(0x86, 0, result=1))
    assert not value.supported


def test_null_message_is_not_ready_error():
    with pytest.raises(DDCError, match="null message"):
        parse_get_vcp_reply(0x86, make_reply(b""))


def test_reply_for_other_code_is_rejected():
    with pytest.raises(DDCError):
        parse_get_vcp_reply(0x12, vcp_reply(0x10, 85))


def test_bad_checksum_is_rejected():
    reply = bytearray(vcp_reply(0x10, 85))
    reply[-1] ^= 0x01
    with pytest.raises(DDCError):
        extract_reply_body(bytes(reply))


def test_client_reads_value_through_transport():
    display = FakeDisplay({0x10: 85})
    assert client(display).get_vcp(0x10).current == 85
    expected = (0x37, 0x51, build_get_vcp_request(0x10))
    assert display.writes == [expected, expected]


def test_client_retries_after_corrupted_reply():
    display = FakeDisplay({0x10: 85}, corrupt_reads=2)
    assert client(display).get_vcp(0x10).current == 85
    assert len(display.writes) == 6


def test_client_gives_up_after_retries():
    display = FakeDisplay({0x10: 85}, corrupt_reads=10)
    with pytest.raises(DDCError):
        client(display).get_vcp(0x10)


def test_read_capabilities_joins_chunks():
    caps = b"(prot(monitor)type(LCD)model(346B1C)vcp(02 04 10 12 14(05 08 0B) 60 86))"
    display = FakeDisplay({}, capabilities=caps)
    assert client(display).read_capabilities() == caps.decode()


def test_set_vcp_request_layout():
    request = build_set_vcp_request(0x86, 0x0004)
    assert request[:5] == bytes([0x84, 0x03, 0x86, 0x00, 0x04])
    assert request[5] == xor_checksum(0x6E ^ 0x51, request[:5])


def test_set_vcp_writes_value_and_verifies_it():
    display = FakeDisplay({0x86: 8})
    value = client(display).set_vcp(0x86, 4)
    assert value.current == 4
    assert display.values[0x86] == 4
    assert display.writes[0][2] == build_set_vcp_request(0x86, 4)


def test_set_vcp_tolerates_busy_display_while_verifying():
    display = FakeDisplay({0x86: 8}, corrupt_reads=6)
    assert client(display).set_vcp(0x86, 4).current == 4


def test_set_vcp_fails_when_display_keeps_old_value():
    display = FakeDisplay({0x86: 8}, ignore_sets=True)
    with pytest.raises(DDCError, match="did not become 4"):
        client(display).set_vcp(0x86, 4)
