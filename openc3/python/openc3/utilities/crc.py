# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import struct


# Abstract base class which {Crc16}, {Crc32} and {Crc64} use. Do NOT use this
# class directly but instead use one of the subclasses.
class Crc:
    BIT_REVERSE_TABLE = [
        0x00,
        0x80,
        0x40,
        0xC0,
        0x20,
        0xA0,
        0x60,
        0xE0,
        0x10,
        0x90,
        0x50,
        0xD0,
        0x30,
        0xB0,
        0x70,
        0xF0,
        0x08,
        0x88,
        0x48,
        0xC8,
        0x28,
        0xA8,
        0x68,
        0xE8,
        0x18,
        0x98,
        0x58,
        0xD8,
        0x38,
        0xB8,
        0x78,
        0xF8,
        0x04,
        0x84,
        0x44,
        0xC4,
        0x24,
        0xA4,
        0x64,
        0xE4,
        0x14,
        0x94,
        0x54,
        0xD4,
        0x34,
        0xB4,
        0x74,
        0xF4,
        0x0C,
        0x8C,
        0x4C,
        0xCC,
        0x2C,
        0xAC,
        0x6C,
        0xEC,
        0x1C,
        0x9C,
        0x5C,
        0xDC,
        0x3C,
        0xBC,
        0x7C,
        0xFC,
        0x02,
        0x82,
        0x42,
        0xC2,
        0x22,
        0xA2,
        0x62,
        0xE2,
        0x12,
        0x92,
        0x52,
        0xD2,
        0x32,
        0xB2,
        0x72,
        0xF2,
        0x0A,
        0x8A,
        0x4A,
        0xCA,
        0x2A,
        0xAA,
        0x6A,
        0xEA,
        0x1A,
        0x9A,
        0x5A,
        0xDA,
        0x3A,
        0xBA,
        0x7A,
        0xFA,
        0x06,
        0x86,
        0x46,
        0xC6,
        0x26,
        0xA6,
        0x66,
        0xE6,
        0x16,
        0x96,
        0x56,
        0xD6,
        0x36,
        0xB6,
        0x76,
        0xF6,
        0x0E,
        0x8E,
        0x4E,
        0xCE,
        0x2E,
        0xAE,
        0x6E,
        0xEE,
        0x1E,
        0x9E,
        0x5E,
        0xDE,
        0x3E,
        0xBE,
        0x7E,
        0xFE,
        0x01,
        0x81,
        0x41,
        0xC1,
        0x21,
        0xA1,
        0x61,
        0xE1,
        0x11,
        0x91,
        0x51,
        0xD1,
        0x31,
        0xB1,
        0x71,
        0xF1,
        0x09,
        0x89,
        0x49,
        0xC9,
        0x29,
        0xA9,
        0x69,
        0xE9,
        0x19,
        0x99,
        0x59,
        0xD9,
        0x39,
        0xB9,
        0x79,
        0xF9,
        0x05,
        0x85,
        0x45,
        0xC5,
        0x25,
        0xA5,
        0x65,
        0xE5,
        0x15,
        0x95,
        0x55,
        0xD5,
        0x35,
        0xB5,
        0x75,
        0xF5,
        0x0D,
        0x8D,
        0x4D,
        0xCD,
        0x2D,
        0xAD,
        0x6D,
        0xED,
        0x1D,
        0x9D,
        0x5D,
        0xDD,
        0x3D,
        0xBD,
        0x7D,
        0xFD,
        0x03,
        0x83,
        0x43,
        0xC3,
        0x23,
        0xA3,
        0x63,
        0xE3,
        0x13,
        0x93,
        0x53,
        0xD3,
        0x33,
        0xB3,
        0x73,
        0xF3,
        0x0B,
        0x8B,
        0x4B,
        0xCB,
        0x2B,
        0xAB,
        0x6B,
        0xEB,
        0x1B,
        0x9B,
        0x5B,
        0xDB,
        0x3B,
        0xBB,
        0x7B,
        0xFB,
        0x07,
        0x87,
        0x47,
        0xC7,
        0x27,
        0xA7,
        0x67,
        0xE7,
        0x17,
        0x97,
        0x57,
        0xD7,
        0x37,
        0xB7,
        0x77,
        0xF7,
        0x0F,
        0x8F,
        0x4F,
        0xCF,
        0x2F,
        0xAF,
        0x6F,
        0xEF,
        0x1F,
        0x9F,
        0x5F,
        0xDF,
        0x3F,
        0xBF,
        0x7F,
        0xFF,
    ]

    # Creates a CRC algorithm instance.
    #
    # self.param poly [Integer] Polynomial to use when calculating the CRC
    # self.param seed [Integer] Seed value to start the calculation
    # self.param xor [Boolean] Whether to XOR the CRC result with 0xFFFF
    # self.param reflect [Boolean] Whether to bit reverse each byte of data before
    #   calculating the CRC
    def __init__(self, poly, seed, xor, reflect):
        self.poly = poly
        self.seed = seed
        self.xor = xor
        self.reflect = reflect
        self.table = []

        # Determine which class we're using= Crc8, Crc16, Crc32, Crc64
        match self.__class__.__name__:
            case "Crc8":
                self.bit_size = 8
                pack = ">B"
                filter_mask = 0xFF
            case "Crc16":
                self.bit_size = 16
                pack = ">H"
                filter_mask = 0xFFFF
            case "Crc32":
                self.bit_size = 32
                pack = ">I"
                filter_mask = 0xFFFFFFFF
            case "Crc64":
                self.bit_size = 64
                pack = ">Q"
                filter_mask = 0xFFFFFFFFFFFFFFFF
        for index in range(0, 256):
            self.table.append(
                int.from_bytes(
                    struct.pack(
                        pack,
                        self.compute_table_entry(index, self.bit_size) & filter_mask,
                    ),
                    byteorder="big",
                )
            )

    # self.!method calc(data, seed = None)
    #   Calculates the CRC across the data buffer using the optional seed.
    #   Implemented in C for speed.
    #
    #   self.param data [String] String buffer of binary data to calculate a CRC on
    #   self.param seed [Integer|None] Seed value to start the calculation. Pass None
    #     to use the default seed set in the constructor.
    #   self.return [Integer] The CRC value

    # Bit reverse the 8 bit value
    # self.param value [Integer]
    # self.return [Integer] Bit reversed value
    def bit_reverse_8(self, value):
        return Crc.BIT_REVERSE_TABLE[value & 0xFF]

    def bit_reverse_16(self, value):
        return (Crc.BIT_REVERSE_TABLE[value & 0xFF] << 8) | (Crc.BIT_REVERSE_TABLE[(value >> 8) & 0xFF])

    def bit_reverse_32(self, value):
        return (
            (Crc.BIT_REVERSE_TABLE[value & 0xFF] << 24)
            | (Crc.BIT_REVERSE_TABLE[(value >> 8) & 0xFF] << 16)
            | (Crc.BIT_REVERSE_TABLE[(value >> 16) & 0xFF] << 8)
            | (Crc.BIT_REVERSE_TABLE[(value >> 24) & 0xFF])
        )

    def bit_reverse_64(self, value):
        return (
            (Crc.BIT_REVERSE_TABLE[value & 0x00000000000000FF] << 56)
            | (Crc.BIT_REVERSE_TABLE[(value >> 8) & 0x00000000000000FF] << 48)
            | (Crc.BIT_REVERSE_TABLE[(value >> 16) & 0x00000000000000FF] << 40)
            | (Crc.BIT_REVERSE_TABLE[(value >> 24) & 0x00000000000000FF] << 32)
            | (Crc.BIT_REVERSE_TABLE[(value >> 32) & 0x00000000000000FF] << 24)
            | (Crc.BIT_REVERSE_TABLE[(value >> 40) & 0x00000000000000FF] << 16)
            | (Crc.BIT_REVERSE_TABLE[(value >> 48) & 0x00000000000000FF] << 8)
            | (Crc.BIT_REVERSE_TABLE[(value >> 56) & 0x00000000000000FF])
        )

    def calc(self, data, seed=None):
        if seed is None:
            seed = self.seed
        crc = seed

        match self.bit_size:
            case 8:
                right_shift = 0
                filter_mask = 0xFF
                final_bit_reverse = self.bit_reverse_8
            case 16:
                right_shift = 8
                filter_mask = 0xFFFF
                final_bit_reverse = self.bit_reverse_16
            case 32:
                right_shift = 24
                filter_mask = 0xFFFFFFFF
                final_bit_reverse = self.bit_reverse_32
            case 64:
                right_shift = 56
                filter_mask = 0xFFFFFFFFFFFFFFFF
                final_bit_reverse = self.bit_reverse_64

        if self.reflect:
            for byte in data:
                if isinstance(byte, str):
                    byte = ord(byte)
                crc = (crc << 8 & filter_mask) ^ self.table[(crc >> right_shift) ^ self.bit_reverse_8(byte)]

            final_bit_reverse(crc ^ filter_mask)
            if self.xor:
                return final_bit_reverse(crc ^ filter_mask)
            else:
                return final_bit_reverse(crc)
        else:
            for byte in data:
                if isinstance(byte, str):
                    byte = ord(byte)
                crc = ((crc << 8) & filter_mask) ^ self.table[(crc >> right_shift) ^ byte]

            if self.xor:
                return crc ^ filter_mask
            else:
                return crc

    # Compute a single entry in the crc lookup table
    def compute_table_entry(self, index, digits):
        # Start by shifting the index
        crc = index << (digits - 8)

        # The mask is 0x8000 for Crc16, 0x80000000 for Crc32, etc
        mask = 1 << (digits - 1)

        for _ in range(0, 8):
            if (crc & mask) != 0:
                crc = crc << 1 ^ self.poly
            else:
                crc = crc << 1

        # XOR the mask and or back in the top bit to get all ones
        mask = ~mask | mask
        return crc & mask


# Calculates 8-bit CRCs over a buffer of data.
class Crc8(Crc):
    # CRC-8-DVB-S2 default polynomial
    DEFAULT_POLY = 0xD5
    # Seed for 8-bit CRC
    DEFAULT_SEED = 0x00

    # Creates a 8 bit CRC algorithm instance. By default it is initialized to
    # use the CRC-8-DVB-S2 algorithm.
    #
    # self.param poly [Integer] Polynomial to use when calculating the CRC
    # self.param seed [Integer] Seed value to start the calculation
    # self.param xor [Boolean] Whether to XOR the CRC result with 0xFF
    # self.param reflect [Boolean] Whether to bit reverse each byte of data before
    #   calculating the CRC
    def __init__(self, poly=DEFAULT_POLY, seed=DEFAULT_SEED, xor=False, reflect=False):
        super().__init__(poly, seed, xor, reflect)


# Calculates 16-bit CRCs over a buffer of data.
class Crc16(Crc):
    # CRC-16-CCITT default polynomial
    DEFAULT_POLY = 0x1021
    # Seed for 16-bit CRC
    DEFAULT_SEED = 0xFFFF

    # Creates a 16 bit CRC algorithm instance. By default it is initialized to
    # use the CRC-16-CCITT algorithm.
    #
    # self.param poly [Integer] Polynomial to use when calculating the CRC
    # self.param seed [Integer] Seed value to start the calculation
    # self.param xor [Boolean] Whether to XOR the CRC result with 0xFFFF
    # self.param reflect [Boolean] Whether to bit reverse each byte of data before
    #   calculating the CRC
    def __init__(self, poly=DEFAULT_POLY, seed=DEFAULT_SEED, xor=False, reflect=False):
        super().__init__(poly, seed, xor, reflect)


# Calculates 32-bit CRCs over a buffer of data.
class Crc32(Crc):
    # CRC-32 default polynomial
    DEFAULT_POLY = 0x04C11DB7
    # Default Seed for 32-bit CRC
    DEFAULT_SEED = 0xFFFFFFFF

    # Creates a 32 bit CRC algorithm instance. By default it is initialized to
    # use the CRC-32 algorithm.
    #
    # self.param poly [Integer] Polynomial to use when calculating the CRC
    # self.param seed [Integer] Seed value to start the calculation
    # self.param xor [Boolean] Whether to XOR the CRC result with 0xFFFF
    # self.param reflect [Boolean] Whether to bit reverse each byte of data before
    #   calculating the CRC
    def __init__(self, poly=DEFAULT_POLY, seed=DEFAULT_SEED, xor=True, reflect=True):
        super().__init__(poly, seed, xor, reflect)


# Calculates 64-bit CRCs over a buffer of data.
class Crc64(Crc):
    # CRC-64-ECMA default polynomial
    DEFAULT_POLY = 0x42F0E1EBA9EA3693
    # Default Seed for 64-bit CRC
    DEFAULT_SEED = 0xFFFFFFFFFFFFFFFF

    # Creates a 64 bit CRC algorithm instance. By default it is initialized to
    # use the algorithm.
    #
    # self.param poly [Integer] Polynomial to use when calculating the CRC
    # self.param seed [Integer] Seed value to start the calculation
    # self.param xor [Boolean] Whether to XOR the CRC result with 0xFFFF
    # self.param reflect [Boolean] Whether to bit reverse each byte of data before
    #   calculating the CRC
    def __init__(self, poly=DEFAULT_POLY, seed=DEFAULT_SEED, xor=True, reflect=True):
        super().__init__(poly, seed, xor, reflect)
