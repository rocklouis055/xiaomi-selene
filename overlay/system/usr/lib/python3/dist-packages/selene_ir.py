#!/usr/bin/env python3
"""selene_ir - send infrared remote codes from Ubuntu Touch on the Redmi 10.

The IR LED is driven by MediaTek's irtx PWM driver (/dev/irtx). Android's
consumer-IR HAL (/vendor/lib64/hw/consumerir.common.so) turns a pattern of
mark/space durations into the raw PWM bitstream the driver wants; it is loaded
here through libhybris (hw_get_module), exactly like Android does.

    python3 selene_ir.py --info
    python3 selene_ir.py 38000 9000 4500 560 560 560 1690 ...   (carrier Hz, then µs)
    python3 selene_ir.py --nec 0x04 0x08                          (NEC address, command)

As a module:
    from selene_ir import ConsumerIR, nec
    ir = ConsumerIR()
    ir.transmit(38000, nec(0x04, 0x08))
"""
import ctypes as C
import sys

_P = C.c_void_p


class _HwModule(C.Structure):          # hw_module_t (hardware/libhardware/include/hardware/hardware.h)
    _fields_ = [("tag", C.c_uint32), ("module_api_version", C.c_uint16),
                ("hal_api_version", C.c_uint16), ("id", C.c_char_p), ("name", C.c_char_p),
                ("author", C.c_char_p), ("methods", _P), ("dso", _P),
                ("reserved", C.c_uint64 * (32 - 7))]


_OPEN = C.CFUNCTYPE(C.c_int, C.POINTER(_HwModule), C.c_char_p, C.POINTER(_P))


class _HwModuleMethods(C.Structure):
    _fields_ = [("open", _OPEN)]


class _CarrierRange(C.Structure):      # consumerir_freq_range_t
    _fields_ = [("min", C.c_int), ("max", C.c_int)]


_TRANSMIT = C.CFUNCTYPE(C.c_int, _P, C.c_int, C.POINTER(C.c_int), C.c_int)
_NUM_FREQS = C.CFUNCTYPE(C.c_int, _P)
_GET_FREQS = C.CFUNCTYPE(C.c_int, _P, C.c_size_t, C.POINTER(_CarrierRange))


class _ConsumerIrDevice(C.Structure):  # consumerir_device_t
    _fields_ = [("tag", C.c_uint32), ("version", C.c_uint32), ("module", _P),
                ("reserved", C.c_uint64 * 12), ("close", _P),
                ("transmit", _TRANSMIT), ("get_num_carrier_freqs", _NUM_FREQS),
                ("get_carrier_freqs", _GET_FREQS), ("reserved2", C.c_uint64 * 8)]


class ConsumerIR:
    def __init__(self):
        hw = C.CDLL("libhardware.so.2")
        hw.hw_get_module.argtypes = [C.c_char_p, C.POINTER(C.POINTER(_HwModule))]
        module = C.POINTER(_HwModule)()
        rc = hw.hw_get_module(b"consumerir", C.byref(module))
        if rc or not module:
            raise OSError(f"consumerir HAL not found ({rc})")
        methods = C.cast(module.contents.methods, C.POINTER(_HwModuleMethods)).contents
        dev = _P()
        rc = methods.open(module, b"transmitter", C.byref(dev))  # MTK HAL compares the id with "transmitter"
        if rc or not dev:
            raise OSError(f"cannot open consumerir device ({rc}); is /dev/irtx accessible?")
        self._dev = C.cast(dev, C.POINTER(_ConsumerIrDevice)).contents
        self._raw = dev

    def carrier_ranges(self):
        n = self._dev.get_num_carrier_freqs(self._raw)
        if n <= 0:
            return []
        arr = (_CarrierRange * n)()
        n = self._dev.get_carrier_freqs(self._raw, n, arr)
        return [(r.min, r.max) for r in arr[:max(n, 0)]]

    def transmit(self, carrier_hz, pattern_us):
        """Send alternating on/off durations in microseconds (starting with 'on')."""
        pat = (C.c_int * len(pattern_us))(*pattern_us)
        rc = self._dev.transmit(self._raw, int(carrier_hz), pat, len(pattern_us))
        if rc < 0:
            raise OSError(f"transmit failed ({rc})")
        return rc


def nec(address, command):
    """NEC protocol frame (the most common TV/AC remote format), 38 kHz."""
    pattern = [9000, 4500]
    for byte in (address, ~address & 0xFF, command, ~command & 0xFF):
        for bit in range(8):
            pattern += [560, 1690 if (byte >> bit) & 1 else 560]
    pattern.append(560)
    return pattern


def main(argv):
    ir = ConsumerIR()
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
    elif argv[0] == "--info":
        print("carrier ranges (Hz):", ir.carrier_ranges())
    elif argv[0] == "--nec":
        ir.transmit(38000, nec(int(argv[1], 0), int(argv[2], 0)))
        print("sent NEC", argv[1], argv[2])
    else:
        ir.transmit(int(argv[0]), [int(v) for v in argv[1:]])
        print("sent", len(argv) - 1, "durations")


if __name__ == "__main__":
    main(sys.argv[1:])
