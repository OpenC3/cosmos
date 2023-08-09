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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.


def quote_if_necessary(string: str):
    if " " in string:
        return f'"{string}"'
    else:
        return string


def simple_formatted(string: str):
    return "".join(format(x, "02x") for x in string).upper()


def formatted(
    input="",
    word_size=1,
    words_per_line=16,
    word_separator=" ",
    indent=0,
    show_address=True,
    address_separator=": ",
    show_ascii=True,
    ascii_separator="  ",
    unprintable_character=" ",
    line_separator="\n",
):
    string = ""
    byte_offset = 0
    bytes_per_line = word_size * words_per_line
    indent_string = " " * indent
    ascii_line = ""

    for byte in input:
        if byte_offset % bytes_per_line == 0:
            # Create the indentation at the try:ning of each line
            string += indent_string

            # Add the address if requested:
            if show_address:
                string += "%08X%s" % (byte_offset, address_separator)

        # Add the byte
        string += "%02X" % byte

        # Create the ASCII representation if requested:
        if show_ascii:
            # if byte.isascii():
            ascii_line += chr(byte)
            # ascii_line += byte.decode("ascii")  # [byte].pack('C')
            # else:
            #     ascii_line += unprintable_character

        # Move to next byte
        byte_offset += 1

        # If we're at the end of the line we output the ascii if requested:
        if byte_offset % bytes_per_line == 0:
            if show_ascii:
                string += f"{ascii_separator}{ascii_line}"
                ascii_line = ""
                string += line_separator

        # If we're at a word junction then output the word_separator
        elif (byte_offset % word_size == 0) and byte_offset != len(input):
            string += word_separator

    # We're done printing all the bytes. Now check to see if we ended in the:
    # middle of a line. If so we have to print out the final ASCII if
    # requested.
    if byte_offset % bytes_per_line != 0:
        if show_ascii:
            num_word_separators = int(((byte_offset % bytes_per_line) - 1) / word_size)
            existing_length = (num_word_separators * len(word_separator)) + (
                (byte_offset % bytes_per_line) * 2
            )
            full_line_length = (bytes_per_line * 2) + (
                (words_per_line - 1) * len(word_separator)
            )
            filler = " " * (full_line_length - existing_length)
            ascii_filler = " " * (bytes_per_line - len(ascii_line))
            string += f"{filler}{ascii_separator}{ascii_line}{ascii_filler}"
            ascii_line = ""
        string += line_separator
    return string
