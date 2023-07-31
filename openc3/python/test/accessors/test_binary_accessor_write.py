#!/usr/bin/env python3

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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.accessors.binary_accessor import BinaryAccessor


class TestBinaryAccessorWrite(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        self.baseline_data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )

    def test_complains_about_unknown_data_types(self):
        self.assertRaisesRegex(
            AttributeError,
            f"data_type BLOB is not recognized",
            BinaryAccessor.write,
            0,
            0,
            32,
            "BLOB",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_bit_offsets_before_the_beginning_the_buffer(self):
        self.assertRaisesRegex(
            AttributeError,
            f"{len(self.data)} byte buffer insufficient to write STRING at bit_offset {-((len(self.data) * 8) + 8)} with bit_size 32",
            BinaryAccessor.write,
            "",
            -((len(self.data) * 8) + 8),
            32,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_a_negative_bit_offset_and_zero_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            r"negative or zero bit_sizes \(0\) cannot be given with negative bit_offsets \(-8\)",
            BinaryAccessor.write,
            "",
            -8,
            0,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_a_negative_bit_offset_and_negative_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            r"negative or zero bit_sizes \(-8\) cannot be given with negative bit_offsets \(-8\)",
            BinaryAccessor.write,
            "",
            -8,
            -8,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_negative_or_zero_bit_sizes_with_data_types_other_than_string_and_block(
        self,
    ):
        self.assertRaisesRegex(
            AttributeError,
            "bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.write,
            0,
            0,
            -8,
            "INT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertRaisesRegex(
            AttributeError,
            "bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.write,
            0,
            0,
            -8,
            "UINT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertRaisesRegex(
            AttributeError,
            "bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.write,
            0,
            0,
            -8,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_writes_aligned_strings(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            expected_data = self.baseline_data[:]
            first_byte_index = int(bit_offset / 8)
            if first_byte_index > 0:
                expected_data[0:first_byte_index] = b"\x00" * first_byte_index

            BinaryAccessor.write(
                self.baseline_data[first_byte_index:],
                bit_offset,
                (len(self.data) * 8) - bit_offset,
                "STRING",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, expected_data)

    def test_writes_variable_length_strings_with_a_zero_and_negative_bit_size(self):
        for bit_size in range(0, -(len(self.baseline_data)) * 8, -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            expected_data = self.baseline_data[:] + bytearray(
                b"\x00" * -int(bit_size / 8)
            )
            BinaryAccessor.write(
                self.baseline_data,
                0,
                bit_size,
                "STRING",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, expected_data)

    # def test_writes strings with negative bit_offsets(self):
    #   BinaryAccessor.write(self.baseline_data[14..15], -16, 16, 'STRING', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, ("\x00" * 14) + self.baseline_data[14..15])
    #

    # def test_complains about unaligned strings(self):
    #   expect { BinaryAccessor.write('', 1, 32, 'STRING', self.data, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "bit_offset 1 is not byte aligned for data_type STRING")
    #

    # def test_writes aligned blocks(self):
    #   0.step((len(self.data) - 1) * 8, 8) do |bit_offset|
    #     self.data = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    #     expected_data = self.baseline_data.clone
    #     first_byte_index = bit_offset / 8
    #     if first_byte_index > 0
    #       expected_data[0..(first_byte_index - 1)] = "\x00" * first_byte_index
    #
    #     BinaryAccessor.write(self.baseline_data[first_byte_index..-1], bit_offset, (len(self.data) * 8) - bit_offset, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #     self.assertEqual(self.data, expected_data)
    #
    #

    # def test_writes variable length blocks with a zero and negative bit_size(self):
    #   0.step(-(len(self.data) * 8), -8) do |bit_size|
    #     self.data = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    #     expected_data = self.baseline_data.clone + ("\x00" * -(bit_size / 8))
    #     BinaryAccessor.write(self.baseline_data, 0, bit_size, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #     self.assertEqual(self.data, expected_data)
    #
    #

    #   def test_writes a block to an empty buffer(self):
    #     data = ''
    #     512.times do |index|
    #       data << [index].pack("n")
    #
    #     buffer = ""
    #     expect { BinaryAccessor.write(data, 0, -16, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "0 byte buffer insufficient to write BLOCK at bit_offset 0 with bit_size -16")
    #

    #   def test_handles a huge bit offset with small buffer(self):
    #     data = ''
    #     512.times do |index|
    #       data << [index].pack("n")
    #
    #     buffer = ""
    #     expect { BinaryAccessor.write(data, 1024, 0, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "0 byte buffer insufficient to write BLOCK at bit_offset 1024 with bit_size 0")
    #

    #   def test_handles an edge case bit offset(self):
    #     data = ''
    #     512.times do |index|
    #       data << [index].pack("n")
    #
    #     buffer = "\x00" * 127
    #     expect { BinaryAccessor.write(data, 1024, 0, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "127 byte buffer insufficient to write BLOCK at bit_offset 1024 with bit_size 0")
    #

    #   def test_writes a block to a small buffer preserving the (self):
    #     data = ''
    #     512.times do |index|
    #       data << [index].pack("n")
    #
    #     preserve = [0xBEEF].pack("n")
    #     buffer = preserve.clone # Should preserve this
    #     BinaryAccessor.write(data, 0, -16, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR')
    #     expect(buffer[0..-3]).to eql data
    #     expect(buffer[-2..-1]).to eql preserve
    #     data = BinaryAccessor.read(0, data.length * 8 + 16, 'BLOCK', buffer, 'BIG_ENDIAN')
    #     expect(data).to eql buffer
    #

    #   def test_writes a block to another small buffer preserving the (self):
    #     data = ''
    #     512.times do |index|
    #       data << [index].pack("n")
    #
    #     preserve = [0xBEEF0123].pack("N")
    #     buffer = "\x00\x01" + preserve.clone # Should preserve this
    #     BinaryAccessor.write(data, 16, -32, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR')
    #     expect(buffer[0..1]).to eql "\x00\x01"
    #     expect(buffer[2..-5]).to eql data
    #     expect(buffer[-4..-1]).to eql preserve
    #     data = BinaryAccessor.read(0, 16 + data.length * 8 + 32, 'BLOCK', buffer, 'BIG_ENDIAN')
    #     expect(data).to eql buffer
    #

    #   def test_writes a block to a small buffer overwriting the (self):
    #     data = ''
    #     512.times do |index|
    #       data << [index].pack("n")
    #
    #     preserve = [0xBEEF].pack("n")
    #     buffer = [0xDEAD].pack("n") # Should write over this
    #     buffer << preserve.clone # Should preserve this
    #     BinaryAccessor.write(data, 0, -16, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR')
    #     expect(buffer[0..-3]).to eql data
    #     expect(buffer[-2..-1]).to eql preserve
    #     data = BinaryAccessor.read(0, data.length * 8 + 16, 'BLOCK', buffer, 'BIG_ENDIAN')
    #     expect(data).to eql buffer
    #

    #   def test_writes a smaller block in the middle of a buffer(self):
    #     data = ''
    #     buffer = ''
    #     256.times do |index|
    #       data << [index].pack("n")
    #
    #     512.times do
    #       buffer << [0xDEAD].pack("n")
    #
    #     expected = buffer.clone
    #     BinaryAccessor.write(data, 128 * 8, -128 * 8, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR')
    #     expect(buffer.length).to eql (128 + 512 + 128)
    #     expect(buffer[0...128]).to eql expected[0...128]
    #     expect(buffer[128...-128]).to eql data
    #     expect(buffer[-128..-1]).to eql expected[0...128]
    #

    #   def test_writes a larger block in the middle of a buffer(self):
    #     data = ''
    #     buffer = ''
    #     256.times do |index|
    #       data << [index].pack("n")
    #
    #     512.times do
    #       buffer << [0xDEAD].pack("n")
    #
    #     expected = buffer.clone
    #     BinaryAccessor.write(data, 384 * 8, -384 * 8, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR')
    #     expect(buffer.length).to eql (384 + 512 + 384)
    #     expect(buffer[0...384]).to eql expected[0...384]
    #     expect(buffer[384...-384]).to eql data
    #     expect(buffer[-384..-1]).to eql expected[0...384]
    #

    #   def test_complains when the negative index exceeds the buffer length(self):
    #     data = "\x01"
    #     buffer = ''
    #     16.times do
    #       buffer << [0xDEAD].pack("n")
    #
    #     expect { BinaryAccessor.write(data, 0, -2024 * 8, 'BLOCK', buffer, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "32 byte buffer insufficient to write BLOCK at bit_offset 0 with bit_size -16192")
    #

    # def test_writes blocks with negative bit_offsets(self):
    #   BinaryAccessor.write(self.baseline_data[0..1], -16, 16, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #   expect(self.data[-2..-1]).to eql(self.baseline_data[0..1])
    #

    # def test_writes a blank string with zero bit size(self):
    #   BinaryAccessor.write('', 0, 0, 'STRING', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, '')
    #

    # def test_writes a blank block with zero bit size(self):
    #   BinaryAccessor.write('', 0, 0, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, '')
    #

    # def test_writes a shorter string with zero bit size(self):
    #   BinaryAccessor.write("\x00\x00\x00\x00\x00\x00\x00\x00", 0, 0, 'STRING', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x00\x00\x00\x00\x00\x00\x00\x00")
    #

    # def test_writes a shorter block with zero bit size(self):
    #   BinaryAccessor.write("\x00\x00\x00\x00\x00\x00\x00\x00", 0, 0, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x00\x00\x00\x00\x00\x00\x00\x00")
    #

    # def test_writes a shorter string and zero fill to the given bit size(self):
    #   self.data = b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
    #   BinaryAccessor.write("\x01\x02\x03\x04\x05\x06\x07\x08", 0, 128, 'STRING', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x01\x02\x03\x04\x05\x06\x07\x08\x00\x00\x00\x00\x00\x00\x00\x00")
    #

    # def test_writes a shorter block and zero fill to the given bit size(self):
    #   self.data = b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
    #   BinaryAccessor.write("\x01\x02\x03\x04\x05\x06\x07\x08", 0, 128, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x01\x02\x03\x04\x05\x06\x07\x08\x00\x00\x00\x00\x00\x00\x00\x00")
    #

    # def test_complains about unaligned blocks(self):
    #   expect { BinaryAccessor.write(self.baseline_data, 7, 16, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "bit_offset 7 is not byte aligned for data_type BLOCK")
    #

    # def test_complains if write exceeds the size of the buffer(self):
    #   expect { BinaryAccessor.write(self.baseline_data, 8, 800, 'STRING', self.data, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError, "16 byte buffer insufficient to write STRING at bit_offset 8 with bit_size 800")
    #

    # def test_truncates the buffer for 0 bitsize(self):
    #   expect(len(self.data)).to eql 16
    #   BinaryAccessor.write("\x01\x02\x03", 8, 0, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x00\x01\x02\x03")
    #   expect(len(self.data)).to eql 4
    #

    # def test_expands the buffer for 0 bitsize(self):
    #   expect(len(self.data)).to eql 16
    #   BinaryAccessor.write("\x01\x02\x03", (14 * 8), 0, 'BLOCK', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03")
    #   expect(len(self.data)).to eql 17
    #

    # def test_writes a frozen string(self):
    #   buffer = "BLANKxxxWORLD"
    #   string = "HELLO".freeze
    #   # Specify 3 more bytes than given to exercise the padding logic
    #   string = BinaryAccessor.write(string, 0, (string.length + 3) * 8, 'STRING', buffer, 'BIG_ENDIAN', 'ERROR')
    #   expect(buffer).to eql("HELLO\x00\x00\x00WORLD")
    #   expect(string).to eql("HELLO")
    #   expect(string.frozen?).to be true
    #

    # def test_complains about writing a frozen buffer(self):
    #   buffer = "BLANK WORLD".freeze
    #   string = "HELLO"
    #   expect { BinaryAccessor.write(string, 0, string.length * 8, 'STRING', buffer, 'BIG_ENDIAN', 'ERROR') }.to raise_error(RuntimeError, /can't modify frozen String/)
    #

    # def test_writes aligned 8-bit unsigned integers(self):
    #   0.step((len(self.data) - 1) * 8, 8) do |bit_offset|
    #     self.data = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    #     byte_index = bit_offset / 8
    #     BinaryAccessor.write(self.baseline_data.getbyte(byte_index), bit_offset, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR')
    #     expect(self.data[byte_index..byte_index]).to eq(self.baseline_data[byte_index..byte_index])
    #
    #

    # def test_writes aligned 8-bit signed integers(self):
    #   0.step((len(self.data) - 1) * 8, 8) do |bit_offset|
    #     self.data = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    #     byte_index = bit_offset / 8
    #     value = self.baseline_data.getbyte(byte_index)
    #     value = value - 256 if value >= 128
    #     BinaryAccessor.write(value, bit_offset, 8, 'INT', self.data, 'BIG_ENDIAN', 'ERROR')
    #     expect(self.data[byte_index..byte_index]).to eql(self.baseline_data[byte_index..byte_index])
    #
    #

    # def test_converts floats when writing integers(self):
    #   self.data = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    #   BinaryAccessor.write(1.0, 0, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR')
    #   BinaryAccessor.write(2.5, 8, 8, 'INT', self.data, 'BIG_ENDIAN', 'ERROR')
    #   BinaryAccessor.write(4.99, 16, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x01\x02\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    #

    # def test_converts integer strings when writing integers(self):
    #   self.data = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    #   BinaryAccessor.write("1", 0, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR')
    #   BinaryAccessor.write("2", 8, 8, 'INT', self.data, 'BIG_ENDIAN', 'ERROR')
    #   BinaryAccessor.write("4", 16, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR')
    #   self.assertEqual(self.data, "\x01\x02\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    #

    # def test_complains about non-integer strings when writing integers(self):
    #   expect { BinaryAccessor.write("1.0", 0, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError)
    #   expect { BinaryAccessor.write("abc123", 0, 8, 'UINT', self.data, 'BIG_ENDIAN', 'ERROR') }.to raise_error(ArgumentError)
    #
