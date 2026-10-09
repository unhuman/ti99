#!/usr/bin/env python3
"""Reject Coleco carts whose CVBasic banks cannot fit the MegaCart window."""

import argparse
import re
from pathlib import Path


ROM_BYTES = 128 * 1024
BANK_CAP = 0x3FBF  # 16 KiB less CVBasic's reserved trailer
BANKS = range(5)  # shared code and the four game banks


def check_layout(rom_size: int, symbols: str) -> dict[str, int]:
    if rom_size != ROM_BYTES:
        raise ValueError(f"Coleco cart is {rom_size} bytes; expected 128 KiB MegaCart")
    values = {
        name.upper(): int(value, 16)
        for name, value in re.findall(
            r"(?m)^([A-Za-z_][A-Za-z_0-9]*):\s+equ\s+([0-9a-fA-F]+)h\s*$",
            symbols,
        )
    }
    for name, expected in (("CVBASIC_BANK_SWITCHING", 1), ("CVBASIC_BANK_ROM_SIZE", 128)):
        if values.get(name) != expected:
            raise ValueError(f"{name} must be {expected}")
    for bank in BANKS:
        name = f"BANK_{bank}_FREE"
        free = values.get(name)
        if free is None or not 0 <= free <= BANK_CAP:
            raise ValueError(f"{name} is missing or outside the 16 KiB bank (value {free})")
    return values


def self_test() -> None:
    good = "CVBASIC_BANK_SWITCHING: equ 1h\nCVBASIC_BANK_ROM_SIZE: equ 80h\n"
    good += "".join(f"BANK_{bank}_FREE: equ 100h\n" for bank in BANKS)
    check_layout(ROM_BYTES, good)
    bad_cases = (
        (40960, good),  # the old unbanked build compiled but could not play level 1
        (ROM_BYTES, good.replace("BANK_0_FREE: equ 100h", "BANK_0_FREE: equ fff0h")),
        (ROM_BYTES, good.replace("BANK_3_FREE: equ 100h\n", "")),
        (ROM_BYTES, good.replace("CVBASIC_BANK_SWITCHING: equ 1h", "CVBASIC_BANK_SWITCHING: equ 0h")),
    )
    for size, symbols in bad_cases:
        try:
            check_layout(size, symbols)
        except ValueError:
            continue
        raise AssertionError("checker accepted a known bad Coleco layout")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom", nargs="?", type=Path)
    parser.add_argument("symbols", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("Coleco layout checker self-test passed")
    if args.rom is not None and args.symbols is not None:
        values = check_layout(args.rom.stat().st_size, args.symbols.read_text(encoding="ascii"))
        free = ", ".join(f"bank {bank}: {values[f'BANK_{bank}_FREE']} free" for bank in BANKS)
        print(f"Coleco MegaCart layout verified: 128 KiB; {free}")
    elif not args.self_test:
        parser.error("rom and symbols are required")


if __name__ == "__main__":
    main()
