# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.


from openc3.conversions.conversion import Conversion


# Performs a polynomial conversion on the value
class PolynomialConversion(Conversion):
    # Initializes the conversion with the given polynomial coefficients. Sets
    # the converted_type to :FLOAT and the converted_bit_size to 64.
    #
    # @param coeffs [Array<Float>] The polynomial coefficients
    def __init__(self, *coeffs):
        super().__init__()
        self.coeffs = [float(coeff) for coeff in coeffs]
        self.converted_type = "FLOAT"
        self.converted_bit_size = 64
        self.params = coeffs

    # @param (see Conversion#call)
    # @return [Float] The value with the polynomial applied
    def call(self, value, myself, buffer):
        value = float(value)

        # Handle C0
        result = self.coeffs[0]

        # Handle Coefficients raised to a power
        raised_to_power = 1.0
        for coeff in self.coeffs[1:]:
            raised_to_power *= value
            result += coeff * raised_to_power
        return result

    # @return [String] Class followed by the list of coefficients
    def __str__(self):
        result = ""
        for index in range(0, len(self.coeffs)):
            if index == 0:
                result += f"{self.coeffs[index]}"
            elif index == 1:
                result += f" + {self.coeffs[index]}x"
            else:
                result += f" + {self.coeffs[index]}x^{index}"
        return result

    # @param (see Conversion#to_config)
    # @return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        return f"    POLY_{read_or_write}_CONVERSION {' '.join(self.coeffs)}\n"
