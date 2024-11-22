# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.config.config_parser import ConfigParser
from openc3.interfaces.protocols.protocol import Protocol
from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.utilities.logger import Logger
from openc3.utilities.crc import Crc8, Crc16, Crc32, Crc64


# Creates a CRC on write and verifies a CRC on read
class CrcProtocol(Protocol):
    ERROR = "ERROR"  # on CRC mismatch
    DISCONNECT = "DISCONNECT"  # on CRC mismatch

    # self.param write_item_name [String/None] Item to fill with calculated CRC value for outgoing packets (None = don't fill)
    # self.param strip_crc [Boolean] Whether or not to remove the CRC from incoming packets
    # self.param bad_strategy [ERROR/DISCONNECT] How to handle CRC errors on incoming packets.  ERROR = Just log the error, DISCONNECT = Disconnect interface
    # self.param bit_offset [Integer] Bit offset of the CRC in the data.  Can be negative to indicate distance from end of packet
    # self.param bit_size [Integer] Bit size of the CRC - Must be 16, 32, or 64
    # self.param endianness [BIG_ENDIAN/LITTLE_ENDIAN] Endianness of the CRC
    # self.param poly [Integer] Polynomial to use when calculating the CRC
    # self.param seed [Integer] Seed value to start the calculation
    # self.param xor [Boolean] Whether to XOR the CRC result with 0xFFFF
    # self.param reflect [Boolean] Whether to bit reverse each byte of data before calculating the CRC
    # self.param allow_empty_data [True/False/None] See Protocol#initialize
    def __init__(
        self,
        write_item_name=None,
        strip_crc=False,
        bad_strategy="ERROR",
        bit_offset=-32,
        bit_size=32,
        endianness="BIG_ENDIAN",
        poly=None,
        seed=None,
        xor=None,
        reflect=None,
        allow_empty_data=None,
    ):
        super().__init__(allow_empty_data)
        self.write_item_name = ConfigParser.handle_none(write_item_name)
        self.strip_crc = ConfigParser.handle_true_false(strip_crc)
        if self.strip_crc is not True and self.strip_crc is not False:
            raise ValueError(f"Invalid strip CRC of '{strip_crc}'. Must be TRUE or FALSE.")

        match bad_strategy:
            case CrcProtocol.ERROR | CrcProtocol.DISCONNECT:
                self.bad_strategy = bad_strategy
            case _:
                raise ValueError(f"Invalid bad CRC strategy of {bad_strategy}. Must be ERROR or DISCONNECT.")

        match str(endianness).upper():
            case "BIG_ENDIAN":
                self.endianness = "BIG_ENDIAN"  # Convert to symbol for use in BinaryAccessor.write
            case "LITTLE_ENDIAN":
                self.endianness = "LITTLE_ENDIAN"  # Convert to symbol for use in BinaryAccessor.write
            case _:
                raise ValueError("Invalid endianness '{endianness}'. Must be BIG_ENDIAN or LITTLE_ENDIAN.")

        try:
            self.bit_offset = int(bit_offset)
        except TypeError:
            raise ValueError(f"Invalid bit offset of {bit_offset}. Must be a number.")
        if self.bit_offset % 8 != 0:
            raise ValueError(f"Invalid bit offset of {bit_offset}. Must be divisible by 8.")

        poly = ConfigParser.handle_none(poly)
        try:
            if isinstance(poly, str):
                poly = int(poly, 0)
        except (ValueError, TypeError):
            raise ValueError(f"Invalid polynomial of {poly}. Must be a number.")

        seed = ConfigParser.handle_none(seed)
        try:
            if isinstance(seed, str):
                seed = int(seed, 0)
        except ValueError:
            raise ValueError(f"Invalid seed of {seed}. Must be a number.")

        xor = ConfigParser.handle_true_false_none(xor)
        if xor is not None and xor is not True and xor is not False:
            raise ValueError(f"Invalid XOR value of '{xor}'. Must be TRUE or FALSE.")

        reflect = ConfigParser.handle_true_false_none(reflect)
        if reflect is not None and reflect is not True and reflect is not False:
            raise ValueError(f"Invalid reflect value of '{reflect}'. Must be TRUE or FALSE.")

        # Built the CRC arguments array. All subsequent arguments are dependent
        # on the previous ones so we build it up incrementally.
        args = []
        if poly is not None:
            args.append(poly)
            if seed is not None:
                args.append(seed)
                if xor is not None:
                    args.append(xor)
                    if reflect is not None:
                        args.append(reflect)

        try:
            self.bit_size = int(bit_size)
        except TypeError:
            raise ValueError(f"Invalid bit size of {bit_size}. Must be a number.")
        endianness = "<"  # LITTLE_ENDIAN
        if self.endianness == "BIG_ENDIAN":
            endianness = ">"
        match self.bit_size:
            case 8:
                self.pack = f"{endianness}B"
                if len(args) == 0:
                    self.crc = Crc8()
                else:
                    self.crc = Crc8(*args)
            case 16:
                self.pack = f"{endianness}H"
                if len(args) == 0:
                    self.crc = Crc16()
                else:
                    self.crc = Crc16(*args)
            case 32:
                self.pack = f"{endianness}I"
                if len(args) == 0:
                    self.crc = Crc32()
                else:
                    self.crc = Crc32(*args)
            case 64:
                self.pack = f"{endianness}Q"
                if len(args) == 0:
                    self.crc = Crc64()
                else:
                    self.crc = Crc64(*args)
            case _:
                raise ValueError(f"Invalid bit size of {bit_size}. Must be 16, 32, or 64.")

    def read_data(self, data, extra):
        if len(data) <= 0:
            return super().read_data(data, extra)

        crc = BinaryAccessor.read(self.bit_offset, self.bit_size, "UINT", data, self.endianness)
        calculated_crc = self.crc.calc(data[0 : int(self.bit_offset / 8)])
        if calculated_crc != crc:
            interface = ""
            if self.interface:
                interface = self.interface.name
            Logger.error(f"{interface}: Invalid CRC detected! Calculated {hex(calculated_crc)} vs found {hex(crc)}.")
            if self.bad_strategy == CrcProtocol.DISCONNECT:
                return ("DISCONNECT", extra)
        if self.strip_crc:
            new_data = data[:]
            new_data = new_data[0 : int(self.bit_offset / 8)]
            end_range = int((self.bit_offset + self.bit_size) / 8)
            if end_range != 0:
                new_data += data[end_range:]
            return (new_data, extra)
        return (data, extra)

    def write_packet(self, packet):
        if self.write_item_name:
            end_range = int(packet.get_item(self.write_item_name).bit_offset / 8)
            crc = self.crc.calc(packet.buffer_no_copy()[0:end_range])
            packet.write(self.write_item_name, crc)
        return packet

    def write_data(self, data, extra):
        if not self.write_item_name:
            if self.bit_size == 64:
                crc = self.crc.calc(data)
                data += b"\x00" * 8
                BinaryAccessor.write((crc >> 32), -64, 32, "UINT", data, self.endianness, "ERROR")
                BinaryAccessor.write((crc & 0xFFFFFFFF), -32, 32, "UINT", data, self.endianness, "ERROR")
            else:
                crc = self.crc.calc(data)
                data += b"\x00" * int(self.bit_size / 8)
                BinaryAccessor.write(
                    crc,
                    -self.bit_size,
                    self.bit_size,
                    "UINT",
                    data,
                    self.endianness,
                    "ERROR",
                )
        return (data, extra)
