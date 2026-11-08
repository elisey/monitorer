"""DDC/CI protocol: request packets, reply parsing and VCP access over an abstract I2C transport.

Packet layout follows VESA DDC/CI. The display listens on I2C address 0x37; the host
sends with source address 0x51 and the display replies with source address 0x6E.
Request checksums cover the destination address (0x6E) and the source byte (0x51);
reply checksums cover the virtual host address (0x50).
"""

import time
from dataclasses import dataclass
from typing import Protocol

DDC_CHIP_ADDRESS = 0x37
DDC_DATA_ADDRESS = 0x51
DISPLAY_WRITE_ADDRESS = 0x6E
HOST_READ_ADDRESS = 0x50

GET_VCP_OPCODE = 0x01
GET_VCP_REPLY_OPCODE = 0x02
SET_VCP_OPCODE = 0x03
CAPABILITIES_OPCODE = 0xF3
CAPABILITIES_REPLY_OPCODE = 0xE3

GET_VCP_REPLY_LENGTH = 11
CAPABILITIES_REPLY_LENGTH = 38


class DDCError(Exception):
    """Raised when the display does not return a valid reply."""


class I2CTransport(Protocol):
    def write(self, chip_address: int, data_address: int, payload: bytes) -> None: ...

    def read(self, chip_address: int, offset: int, length: int) -> bytes: ...


@dataclass(frozen=True)
class VCPValue:
    code: int
    supported: bool
    vcp_type: int = 0
    maximum: int = 0
    current: int = 0


def xor_checksum(initial: int, data: bytes) -> int:
    checksum = initial
    for byte in data:
        checksum ^= byte
    return checksum


def build_request(body: bytes) -> bytes:
    """Wrap a command body into a host-to-display packet (without the 0x51 source byte)."""
    packet = bytes([0x80 | len(body)]) + body
    checksum = xor_checksum(DISPLAY_WRITE_ADDRESS ^ DDC_DATA_ADDRESS, packet)
    return packet + bytes([checksum])


def build_get_vcp_request(code: int) -> bytes:
    return build_request(bytes([GET_VCP_OPCODE, code]))


def build_set_vcp_request(code: int, value: int) -> bytes:
    return build_request(bytes([SET_VCP_OPCODE, code, (value >> 8) & 0xFF, value & 0xFF]))


def build_capabilities_request(offset: int) -> bytes:
    return build_request(bytes([CAPABILITIES_OPCODE, (offset >> 8) & 0xFF, offset & 0xFF]))


def extract_reply_body(reply: bytes) -> bytes:
    """Validate a display-to-host reply and return its body (opcode and payload)."""
    if len(reply) < 3:
        raise DDCError(f"reply too short: {reply.hex(' ')}")
    if reply[0] != DISPLAY_WRITE_ADDRESS:
        raise DDCError(f"unexpected source address: {reply.hex(' ')}")
    if not reply[1] & 0x80:
        raise DDCError(f"length byte has no 0x80 flag: {reply.hex(' ')}")
    length = reply[1] & 0x7F
    if len(reply) < 2 + length + 1:
        raise DDCError(f"reply shorter than declared length {length}: {reply.hex(' ')}")
    checksum = xor_checksum(HOST_READ_ADDRESS, reply[: 2 + length])
    if checksum != reply[2 + length]:
        raise DDCError(f"checksum mismatch: {reply.hex(' ')}")
    return reply[2 : 2 + length]


def parse_get_vcp_reply(code: int, reply: bytes) -> VCPValue:
    body = extract_reply_body(reply)
    if len(body) == 0:
        raise DDCError("display replied with a null message (not ready)")
    if len(body) != 8 or body[0] != GET_VCP_REPLY_OPCODE:
        raise DDCError(f"unexpected Get VCP reply body: {body.hex(' ')}")
    result_code, reply_code, vcp_type = body[1], body[2], body[3]
    if reply_code != code:
        raise DDCError(f"reply is for VCP 0x{reply_code:02X}, expected 0x{code:02X}")
    if result_code != 0:
        return VCPValue(code=code, supported=False)
    return VCPValue(
        code=code,
        supported=True,
        vcp_type=vcp_type,
        maximum=(body[4] << 8) | body[5],
        current=(body[6] << 8) | body[7],
    )


def parse_capabilities_reply(offset: int, reply: bytes) -> bytes:
    body = extract_reply_body(reply)
    if len(body) < 3 or body[0] != CAPABILITIES_REPLY_OPCODE:
        raise DDCError(f"unexpected capabilities reply body: {body.hex(' ')}")
    reply_offset = (body[1] << 8) | body[2]
    if reply_offset != offset:
        raise DDCError(f"capabilities reply offset {reply_offset}, expected {offset}")
    return body[3:]


class DDCClient:
    """DDC/CI client with retries for the occasional corrupted reply.

    Each request is written several times in a row: some displays (the Philips 346B1C
    among them) answer with a null message unless the request is repeated.
    """

    def __init__(
        self,
        transport: I2CTransport,
        reply_delay: float = 0.05,
        retries: int = 4,
        write_cycles: int = 2,
        write_gap: float = 0.01,
        verify_polls: int = 10,
        verify_interval: float = 0.3,
        sleep=time.sleep,
    ) -> None:
        self._transport = transport
        self._write_cycles = write_cycles
        self._write_gap = write_gap
        self._reply_delay = reply_delay
        self._retries = retries
        self._verify_polls = verify_polls
        self._verify_interval = verify_interval
        self._sleep = sleep

    def _send(self, request: bytes) -> None:
        for cycle in range(self._write_cycles):
            if cycle:
                self._sleep(self._write_gap)
            self._transport.write(DDC_CHIP_ADDRESS, DDC_DATA_ADDRESS, request)

    def _exchange(self, request: bytes, reply_length: int, parse):
        last_error: DDCError | None = None
        for _ in range(self._retries):
            try:
                self._send(request)
                self._sleep(self._reply_delay)
                reply = self._transport.read(DDC_CHIP_ADDRESS, 0, reply_length)
                return parse(reply)
            except DDCError as error:
                last_error = error
                self._sleep(self._reply_delay)
        raise DDCError(f"no valid reply after {self._retries} attempts: {last_error}")

    def get_vcp(self, code: int) -> VCPValue:
        return self._exchange(
            build_get_vcp_request(code),
            GET_VCP_REPLY_LENGTH,
            lambda reply: parse_get_vcp_reply(code, reply),
        )

    def set_vcp(self, code: int, value: int) -> VCPValue:
        """Write a VCP value and poll until the display reports it back.

        Displays may stay busy for a while after a change (e.g. while rescaling the
        picture), so read errors during polling are tolerated until the polls run out.
        """
        self._send(build_set_vcp_request(code, value))
        last_seen: VCPValue | DDCError | None = None
        for _ in range(self._verify_polls):
            self._sleep(self._verify_interval)
            try:
                last_seen = self.get_vcp(code)
            except DDCError as error:
                last_seen = error
                continue
            if last_seen.supported and last_seen.current == value:
                return last_seen
        raise DDCError(f"VCP 0x{code:02X} did not become {value}; last read: {last_seen}")

    def read_capabilities(self, max_chunks: int = 64) -> str:
        data = b""
        for _ in range(max_chunks):
            offset = len(data)
            chunk = self._exchange(
                build_capabilities_request(offset),
                CAPABILITIES_REPLY_LENGTH,
                lambda reply: parse_capabilities_reply(offset, reply),
            )
            if not chunk:
                break
            data += chunk
        return data.rstrip(b"\x00").decode("ascii", errors="replace")
