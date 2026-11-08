"""I2C transport for external displays on Apple Silicon via the private IOAVService API."""

import ctypes
import ctypes.util

from .ddc import DDCError

_iokit = ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))
_cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))

_io_object_t = ctypes.c_uint32
_kCFStringEncodingUTF8 = 0x08000100
_kIOMainPortDefault = 0

_cf.CFStringCreateWithCString.restype = ctypes.c_void_p
_cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
_cf.CFStringGetCString.restype = ctypes.c_bool
_cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
_cf.CFGetTypeID.restype = ctypes.c_ulong
_cf.CFGetTypeID.argtypes = [ctypes.c_void_p]
_cf.CFStringGetTypeID.restype = ctypes.c_ulong
_cf.CFStringGetTypeID.argtypes = []
_cf.CFRelease.restype = None
_cf.CFRelease.argtypes = [ctypes.c_void_p]

_iokit.IOServiceMatching.restype = ctypes.c_void_p
_iokit.IOServiceMatching.argtypes = [ctypes.c_char_p]
_iokit.IOServiceGetMatchingServices.restype = ctypes.c_int
_iokit.IOServiceGetMatchingServices.argtypes = [
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.POINTER(_io_object_t),
]
_iokit.IOIteratorNext.restype = _io_object_t
_iokit.IOIteratorNext.argtypes = [_io_object_t]
_iokit.IOObjectRelease.restype = ctypes.c_int
_iokit.IOObjectRelease.argtypes = [_io_object_t]
_iokit.IORegistryEntryCreateCFProperty.restype = ctypes.c_void_p
_iokit.IORegistryEntryCreateCFProperty.argtypes = [
    _io_object_t,
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_uint32,
]
_iokit.IOAVServiceCreateWithService.restype = ctypes.c_void_p
_iokit.IOAVServiceCreateWithService.argtypes = [ctypes.c_void_p, _io_object_t]
_iokit.IOAVServiceReadI2C.restype = ctypes.c_int
_iokit.IOAVServiceReadI2C.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.c_uint32,
]
_iokit.IOAVServiceWriteI2C.restype = ctypes.c_int
_iokit.IOAVServiceWriteI2C.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    ctypes.c_uint32,
    ctypes.c_void_p,
    ctypes.c_uint32,
]


def _registry_string_property(entry: int, key: str) -> str | None:
    cf_key = _cf.CFStringCreateWithCString(None, key.encode(), _kCFStringEncodingUTF8)
    try:
        value = _iokit.IORegistryEntryCreateCFProperty(entry, cf_key, None, 0)
    finally:
        _cf.CFRelease(cf_key)
    if not value:
        return None
    try:
        if _cf.CFGetTypeID(value) != _cf.CFStringGetTypeID():
            return None
        buffer = ctypes.create_string_buffer(256)
        if not _cf.CFStringGetCString(value, buffer, len(buffer), _kCFStringEncodingUTF8):
            return None
        return buffer.value.decode()
    finally:
        _cf.CFRelease(value)


class IOAVTransport:
    """Raw I2C reads and writes through one IOAVService."""

    def __init__(self, service: int) -> None:
        self._service = service

    def write(self, chip_address: int, data_address: int, payload: bytes) -> None:
        buffer = ctypes.create_string_buffer(payload, len(payload))
        status = _iokit.IOAVServiceWriteI2C(
            self._service, chip_address, data_address, buffer, len(payload)
        )
        if status != 0:
            raise DDCError(f"IOAVServiceWriteI2C failed with 0x{status & 0xFFFFFFFF:08X}")

    def read(self, chip_address: int, offset: int, length: int) -> bytes:
        buffer = ctypes.create_string_buffer(length)
        status = _iokit.IOAVServiceReadI2C(self._service, chip_address, offset, buffer, length)
        if status != 0:
            raise DDCError(f"IOAVServiceReadI2C failed with 0x{status & 0xFFFFFFFF:08X}")
        return buffer.raw


def external_display_transports() -> list[IOAVTransport]:
    """Return one transport per external display port known to the display coprocessor."""
    iterator = _io_object_t()
    status = _iokit.IOServiceGetMatchingServices(
        _kIOMainPortDefault, _iokit.IOServiceMatching(b"DCPAVServiceProxy"), ctypes.byref(iterator)
    )
    if status != 0:
        raise DDCError(f"IOServiceGetMatchingServices failed with 0x{status & 0xFFFFFFFF:08X}")

    transports = []
    try:
        while entry := _iokit.IOIteratorNext(iterator):
            try:
                if _registry_string_property(entry, "Location") != "External":
                    continue
                service = _iokit.IOAVServiceCreateWithService(None, entry)
                if service:
                    transports.append(IOAVTransport(service))
            finally:
                _iokit.IOObjectRelease(entry)
    finally:
        _iokit.IOObjectRelease(iterator)
    return transports
