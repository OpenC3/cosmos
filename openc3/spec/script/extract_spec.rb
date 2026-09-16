# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/script'
require 'tempfile'

module OpenC3
  describe Extract do
    before(:all) do
      setup_system()
      @packet = Packet.new("INST", "ASCIICMD")
      @packet.append_item('STRING', 2048, :STRING)
    end

    describe "extract_string_kwargs_to_args" do
      it "pulls string keyword arguments out of the keyword argument hash" do
        args = [1,2]
        kwargs = {"KEY"=>"VALUE"}
        extract_string_kwargs_to_args(args, kwargs)
        expect(args).to eql([1,2,{"KEY"=>"VALUE"}])
        expect(kwargs).to eql(kwargs)
      end

      it "raises when encountering symbol keyword args" do
        args = [1,2]
        kwargs = {SYMBOL: "VALUE"}
        expect { extract_string_kwargs_to_args(args, kwargs) }.to raise_error(ArgumentError, /Unknown symbol keyword\(s\): SYMBOL/)
      end
    end

    describe "add_cmd_parameter" do
      it "should remove quotes and preserve quoted strings" do
        cmd_params = {}
        add_cmd_parameter('TEST', '"3"', {}, cmd_params)
        expect(cmd_params['TEST']).to eql('3')
      end

      it "should convert unquoted strings to the correct value type" do
        cmd_params = {}
        add_cmd_parameter('TEST', '3', {}, cmd_params)
        expect(cmd_params['TEST']).to eql(3)
        add_cmd_parameter('TEST2', '3.0', {}, cmd_params)
        expect(cmd_params['TEST2']).to eql(3.0)
        add_cmd_parameter('TEST3', '0xA', {}, cmd_params)
        expect(cmd_params['TEST3']).to eql(0xA)
        add_cmd_parameter('TEST4', '3e3', {}, cmd_params)
        expect(cmd_params['TEST4']).to eql(3e3)
        add_cmd_parameter('TEST5', 'Ryan', {}, cmd_params)
        expect(cmd_params['TEST5']).to eql('Ryan')
        add_cmd_parameter('TEST6', '3 4', {}, cmd_params)
        expect(cmd_params['TEST6']).to eql('3 4')
      end

      it "should convert unquoted hex values into binary for blocks and strings" do
        cmd_params = {}
        add_cmd_parameter('STRING', '0xAABBCCDD', @packet.as_json(), cmd_params)
        expect(cmd_params['STRING']).to eql("\xAA\xBB\xCC\xDD")
      end

      it "should preserve quoted hex values for blocks and strings" do
        cmd_params = {}
        add_cmd_parameter('STRING', "'0xAABBCCDD'", @packet.as_json(), cmd_params)
        expect(cmd_params['STRING']).to eql("0xAABBCCDD")
      end
    end

    describe "extract_fields_from_cmd_text" do
      it "should complain about empty strings" do
        expect { extract_fields_from_cmd_text("") }.to raise_error(/text must not be empty/)
      end

      it "should complain about strings that end in with but have no other text" do
        expect { extract_fields_from_cmd_text("TEST COMMAND with") }.to raise_error(/must be followed by parameters/)
        expect { extract_fields_from_cmd_text("TEST COMMAND with            ") }.to raise_error(/must be followed by parameters/)
      end

      it "should complain if target name or packet name are missing" do
        expect { extract_fields_from_cmd_text("TEST") }.to raise_error(/Both Target Name and Command Name must be given/)
      end

      it "should complain if there are too many words before with" do
        expect { extract_fields_from_cmd_text("TEST TEST TEST") }.to raise_error(/Only Target Name and Command Name must be given/)
      end

      it "should complain if any key value pairs are malformed" do
        expect { extract_fields_from_cmd_text("TEST TEST with KEY VALUE, KEY VALUE, VALUE") }.to raise_error(/Missing value for last command parameter/)
        expect { extract_fields_from_cmd_text("TEST TEST with KEY VALUE KEY VALUE") }.to raise_error(/Missing comma in command parameters/)
        expect { extract_fields_from_cmd_text("TEST TEST with KEY VALUE KEY, KEY VALUE") }.to raise_error(/Missing comma in command parameters/)
        expect { extract_fields_from_cmd_text("TEST TEST with KEY VALUE, KEY") }.to raise_error(/Missing value for last command parameter/)
      end

      it "should parse commands correctly" do
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1, KEY2 2, KEY3 '3', KEY4 4.0")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => 'VALUE1', 'KEY2' => 2, 'KEY3' => '3', 'KEY4' => 4.0 }]
        )
      end

      it "should not require whitespace after the comma delimiter" do
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1,KEY2 2,KEY3 '3',KEY4 4.0")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => 'VALUE1', 'KEY2' => 2, 'KEY3' => '3', 'KEY4' => 4.0 }]
        )
        # Mixed spacing around the commas
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1 ,KEY2 2, KEY3 '3' , KEY4 4.0")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => 'VALUE1', 'KEY2' => 2, 'KEY3' => '3', 'KEY4' => 4.0 }]
        )
      end

      it "should allow a trailing comma" do
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1, KEY2 2,")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => 'VALUE1', 'KEY2' => 2 }]
        )
      end

      it "should complain about a leading or duplicated comma" do
        expect { extract_fields_from_cmd_text("TARGET PACKET with ,") }.to raise_error(/Missing command parameter before comma/)
        expect { extract_fields_from_cmd_text("TARGET PACKET with , KEY1 VALUE1") }.to raise_error(/Missing command parameter before comma/)
        expect { extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1,,KEY2 2") }.to raise_error(/Missing command parameter before comma/)
        expect { extract_fields_from_cmd_text("TARGET PACKET with KEY1 VALUE1,,") }.to raise_error(/Missing command parameter before comma/)
      end

      it "should preserve commas inside quoted strings and arrays" do
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 'A,B',KEY2 [1,2,3],KEY3 \"C, D\"")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => 'A,B', 'KEY2' => [1, 2, 3], 'KEY3' => 'C, D' }]
        )
      end

      it "should handle nested array parameters" do
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 [[1,2],[3,4]]")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => [[1, 2], [3, 4]] }]
        )
        # Whitespace inside the nested array and no whitespace around the delimiter
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 [[1, 2], [3, 4]],KEY2 5")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => [[1, 2], [3, 4]], 'KEY2' => 5 }]
        )
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 [['1','2'],['3','4']], KEY2 [[1,2],[3,4]]")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => [['1', '2'], ['3', '4']], 'KEY2' => [[1, 2], [3, 4]] }]
        )
      end

      it "should handle multiple array parameters" do
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 [1,2,3,4], KEY2 2, KEY3 '3', KEY4 [5, 6, 7, 8]")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => [1, 2, 3, 4], 'KEY2' => 2, 'KEY3' => '3', 'KEY4' => [5, 6, 7, 8] }]
        )
        expect(extract_fields_from_cmd_text("TARGET PACKET with KEY1 [1,2,3,4], KEY2 2, KEY3 '3', KEY4 ['1', '2', '3', '4']")).to eql(
          ['TARGET', 'PACKET', { 'KEY1' => [1, 2, 3, 4], 'KEY2' => 2, 'KEY3' => '3', 'KEY4' => ['1', '2', '3', '4'] }]
        )
      end
    end

    describe "extract_fields_from_tlm_text" do
      it "should require exactly TARGET_NAME PACKET_NAME ITEM_NAME" do
        expect { extract_fields_from_tlm_text("") }.to raise_error(/Telemetry Item must be specified as/)
        expect { extract_fields_from_tlm_text("TARGET") }.to raise_error(/Telemetry Item must be specified as/)
        expect { extract_fields_from_tlm_text("TARGET PACKET") }.to raise_error(/Telemetry Item must be specified as/)
        expect { extract_fields_from_tlm_text("TARGET PACKET         ") }.to raise_error(/Telemetry Item must be specified as/)
        expect { extract_fields_from_tlm_text("TARGET PACKET ITEM OTHER") }.to raise_error(/Telemetry Item must be specified as/)
      end

      it "should parse telemetry names correctly" do
        expect(extract_fields_from_tlm_text("TARGET PACKET ITEM")).to eql(['TARGET', 'PACKET', 'ITEM'])
        expect(extract_fields_from_tlm_text("        TARGET         PACKET       ITEM        ")).to eql(['TARGET', 'PACKET', 'ITEM'])
      end
    end

    describe "extract_fields_from_set_tlm_text" do
      it "should complain if formatted incorrectly" do
        expect { extract_fields_from_set_tlm_text("") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET PACKET") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET PACKET ITEM") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET PACKET ITEM=") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET PACKET ITEM=      ") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET PACKET ITEM =") }.to raise_error(/Set Telemetry Item must be specified as/)
        expect { extract_fields_from_set_tlm_text("TARGET PACKET ITEM =     ") }.to raise_error(/Set Telemetry Item must be specified as/)
      end

      it "should parse set_tlm text correctly" do
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM= 5")).to eql(['TARGET', 'PACKET', 'ITEM', 5])
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM = 5")).to eql(['TARGET', 'PACKET', 'ITEM', 5])
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM =5")).to eql(['TARGET', 'PACKET', 'ITEM', 5])
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM=5")).to eql(['TARGET', 'PACKET', 'ITEM', 5])
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM = 5.0")).to eql(['TARGET', 'PACKET', 'ITEM', 5.0])
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM = Ryan")).to eql(['TARGET', 'PACKET', 'ITEM', 'Ryan'])
        expect(extract_fields_from_set_tlm_text("TARGET PACKET ITEM = [1,2,3]")).to eql(['TARGET', 'PACKET', 'ITEM', [1, 2, 3]])
      end
    end

    describe "extract_fields_from_check_text" do
      it "should complain if formatted incorrectly" do
        expect { extract_fields_from_check_text("") }.to raise_error(/Check improperly specified/)
        expect { extract_fields_from_check_text("TARGET") }.to raise_error(/Check improperly specified/)
        expect { extract_fields_from_check_text("TARGET PACKET") }.to raise_error(/Check improperly specified/)
      end

      it "should support no comparison" do
        expect(extract_fields_from_check_text("TARGET PACKET ITEM")).to eql(['TARGET', 'PACKET', 'ITEM', nil])
        expect(extract_fields_from_check_text("TARGET PACKET ITEM             ")).to eql(['TARGET', 'PACKET', 'ITEM', nil])
      end

      it "should support comparisons" do
        expect(extract_fields_from_check_text("TARGET PACKET ITEM == 5")).to eql(['TARGET', 'PACKET', 'ITEM', '== 5'])
        expect(extract_fields_from_check_text("TARGET PACKET ITEM > 5")).to eql(['TARGET', 'PACKET', 'ITEM', '> 5'])
        expect(extract_fields_from_check_text("TARGET PACKET ITEM < 5")).to eql(['TARGET', 'PACKET', 'ITEM', '< 5'])
      end

      it "should support target packet items named the same" do
        expect(extract_fields_from_check_text("TEST TEST TEST == 5")).to eql(['TEST', 'TEST', 'TEST', '== 5'])
      end

      it "should complain about trying to do an = comparison" do
        expect { extract_fields_from_check_text("TARGET PACKET ITEM = 5") }.to raise_error(/ERROR: Use/)
      end

      it "should handle spaces throughout correctly" do
        expect(extract_fields_from_check_text("TARGET PACKET ITEM == \"This   is  a test\"")).to eql(['TARGET', 'PACKET', 'ITEM', "== \"This   is  a test\""])
        expect(extract_fields_from_check_text("TARGET   PACKET  ITEM   ==    'This is  a test   '")).to eql(['TARGET', 'PACKET', 'ITEM', "==    'This is  a test   '"])
      end
    end

    describe "extract_operator_and_operand_from_comparison" do
      it "should parse string operands" do
        expect(extract_operator_and_operand_from_comparison("== 'foo'")).to eql(["==", "foo"])
      end

      it "should parse number operands" do
        expect(extract_operator_and_operand_from_comparison("== 1")).to eql(["==", 1])
      end

      it "should parse list operands" do
        expect(extract_operator_and_operand_from_comparison("in [1, 2, 3]")).to eql(["in", [1, 2, 3]])
      end

      it "should parse nil operands" do
        expect(extract_operator_and_operand_from_comparison("== nil")).to eql(["==", nil])
      end

      it "should complain about invalid operators" do
        expect { extract_operator_and_operand_from_comparison("^ 'foo'") }.to raise_error(/ERROR: Invalid/)
      end

      it "should parse hex, octal and binary operands" do
        expect(extract_operator_and_operand_from_comparison("== 0x0001")).to eql(["==", 1])
        expect(extract_operator_and_operand_from_comparison("== 0o17")).to eql(["==", 15])
        expect(extract_operator_and_operand_from_comparison("== 0b1010")).to eql(["==", 10])
      end

      it "should parse float operands" do
        expect(extract_operator_and_operand_from_comparison("> 1.5")).to eql([">", 1.5])
        expect(extract_operator_and_operand_from_comparison("> 1e5")).to eql([">", 100000.0])
      end

      it "should complain about unparsable operands" do
        expect { extract_operator_and_operand_from_comparison("== 1.2.3") }.to raise_error(/ERROR: Unable/)
      end

      it "should suggest a string for bare word operands" do
        expect { extract_operator_and_operand_from_comparison("== foo") }.to \
          raise_error(NameError, "Uninitialized constant foo. Did you mean 'foo' as a string?")
      end

      it "should process escape sequences using Ruby string literal rules" do
        # Double quoted strings process the full escape set
        expect(extract_operator_and_operand_from_comparison(%q(== "line\nnext"))).to eql(["==", "line\nnext"])
        expect(extract_operator_and_operand_from_comparison(%q(== "tab\there"))).to eql(["==", "tab\there"])
        expect(extract_operator_and_operand_from_comparison(%q(== "quote\"inside"))).to eql(["==", 'quote"inside'])
        # Single quoted strings only escape the backslash and the single quote
        expect(extract_operator_and_operand_from_comparison(%q(== 'line\nnext'))).to eql(["==", 'line\nnext'])
        expect(extract_operator_and_operand_from_comparison(%q(== 'it\'s'))).to eql(["==", "it's"])
      end

      it "should preserve the encoding of a double quoted operand" do
        comparison = %q(== "plain").dup.force_encoding(Encoding::UTF_8)
        expect(extract_operator_and_operand_from_comparison(comparison)[1].encoding).to eql(Encoding::UTF_8)
        # A \xHH escape can produce a byte which is not valid UTF-8
        comparison = %q(== "\xff\xfe").dup.force_encoding(Encoding::UTF_8)
        operand = extract_operator_and_operand_from_comparison(comparison)[1]
        expect(operand.encoding).to eql(Encoding::ASCII_8BIT)
        expect(operand.bytes).to eql([0xFF, 0xFE])
      end

      it "should require a single complete quoted literal" do
        expect { extract_operator_and_operand_from_comparison(%q(== 'a' garbage 'b')) }.to raise_error(/ERROR: Unable to parse operand/)
        expect { extract_operator_and_operand_from_comparison(%q(== 'unterminated)) }.to raise_error(/ERROR: Unable to parse operand/)
      end

      it "should reject ambiguous leading zero integers" do
        # Ruby reads 010 as octal 8 while Python rejects it outright so require 0o10 or 10
        expect { extract_operator_and_operand_from_comparison("== 010") }.to raise_error(/ERROR: Unable to parse operand: 010/)
        expect(extract_operator_and_operand_from_comparison("== 0o10")).to eql(["==", 8])
        expect(extract_operator_and_operand_from_comparison("== 10")).to eql(["==", 10])
        # A leading zero is not ambiguous for a float
        expect(extract_operator_and_operand_from_comparison("== 010.5")).to eql(["==", 10.5])
      end

      it "should parse numbers with underscore separators" do
        expect(extract_operator_and_operand_from_comparison("== 1_000")).to eql(["==", 1000])
        expect(extract_operator_and_operand_from_comparison("== 1_000.5")).to eql(["==", 1000.5])
      end

      it "should support the full set of double quoted escape sequences" do
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{1F600}"))).to eql(["==", "\u{1F600}"])
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{48 49}"))).to eql(["==", "HI"])
        expect(extract_operator_and_operand_from_comparison(%q(== "é"))).to eql(["==", "é"])
        # Octal escapes, e.g. \101 is 'A' and \012 is a newline
        expect(extract_operator_and_operand_from_comparison(%q(== "\101"))).to eql(["==", "A"])
        expect(extract_operator_and_operand_from_comparison(%q(== "\012"))).to eql(["==", "\n"])
        expect(extract_operator_and_operand_from_comparison(%q(== "\0"))[1].bytes).to eql([0])
        # Ruby drops the backslash of an escape which has no special meaning
        expect(extract_operator_and_operand_from_comparison(%q(== "\q"))).to eql(["==", "q"])
      end

      it "should reject escape sequences it does not implement" do
        # Silently dropping the backslash would change the value so these are errors
        expect { extract_operator_and_operand_from_comparison(%q(== "\cA")) }.to raise_error(/Unsupported escape sequence/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\C-A")) }.to raise_error(/Unsupported escape sequence/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\M-A")) }.to raise_error(/Unsupported escape sequence/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\M-\C-A")) }.to raise_error(/Unsupported escape sequence/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\u")) }.to raise_error(/Invalid escape sequence/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\x")) }.to raise_error(/Invalid escape sequence/)
      end

      it "should accept the same unicode codepoints as Ruby" do
        # Ruby allows an empty codepoint list and it produces an empty string
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{}"))).to eql(["==", ""])
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{ }"))).to eql(["==", ""])
        # Up to six hex digits per codepoint, so leading zeros are allowed
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{000048}"))).to eql(["==", "H"])
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{48 000049}"))).to eql(["==", "HI"])
        # The largest character Unicode defines
        expect(extract_operator_and_operand_from_comparison(%q(== "\u{10FFFF}"))).to eql(["==", "\u{10FFFF}"])
      end

      it "should reject unicode codepoints which are not valid characters" do
        # Ruby rejects all of these at parse time. Packing them would silently produce an
        # invalid UTF-8 string which could never match a telemetry value.
        # Above the largest character Unicode defines
        expect { extract_operator_and_operand_from_comparison(%q(== "\u{110000}")) }.to \
          raise_error(/Invalid Unicode codepoint/)
        # The UTF-16 surrogate range is not a character on its own
        expect { extract_operator_and_operand_from_comparison(%q(== "\u{D800}")) }.to \
          raise_error(/Invalid Unicode codepoint/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\uD800")) }.to \
          raise_error(/Invalid Unicode codepoint/)
        expect { extract_operator_and_operand_from_comparison(%q(== "\uDFFF")) }.to \
          raise_error(/Invalid Unicode codepoint/)
        # More than six hex digits
        expect { extract_operator_and_operand_from_comparison(%q(== "\u{0000048}")) }.to \
          raise_error(/Invalid Unicode codepoint/)
        # A bad codepoint anywhere in the list is an error, not a partial string
        expect { extract_operator_and_operand_from_comparison(%q(== "\u{48 110000}")) }.to \
          raise_error(/Invalid Unicode codepoint/)
      end

      it "should reject unescaped string interpolation" do
        # The eval based implementation interpolated this. Interpolating is code execution so
        # it is now an error rather than a silent comparison against the uninterpolated text.
        expect { extract_operator_and_operand_from_comparison(%q(== "Temp #{1 + 1}")) }.to \
          raise_error(/String interpolation is not supported in an operand/)
        expect { extract_operator_and_operand_from_comparison(%q(== "#@ivar")) }.to \
          raise_error(/String interpolation is not supported in an operand/)
        expect { extract_operator_and_operand_from_comparison(%q(== "#$global")) }.to \
          raise_error(/String interpolation is not supported in an operand/)
      end

      it "should keep escaped interpolation and a bare hash as literal text" do
        expect(extract_operator_and_operand_from_comparison(%q(== "\#{1 + 1}"))).to eql(["==", '#{1 + 1}'])
        # Ruby single quoted strings never interpolate
        expect(extract_operator_and_operand_from_comparison(%q(== '#{1 + 1}'))).to eql(["==", '#{1 + 1}'])
        expect(extract_operator_and_operand_from_comparison(%q(== "cost #5"))).to eql(["==", "cost #5"])
      end

      it "should parse list elements with the same rules as a bare operand" do
        expect(extract_operator_and_operand_from_comparison(%q(in ['ON', 'OFF']))).to eql(["in", ["ON", "OFF"]])
        expect(extract_operator_and_operand_from_comparison("in [0xA, 0o17, 1_000]")).to eql(["in", [10, 15, 1000]])
        expect(extract_operator_and_operand_from_comparison("in [true, nil]")).to eql(["in", [true, nil]])
        expect(extract_operator_and_operand_from_comparison("in []")).to eql(["in", []])
        expect(extract_operator_and_operand_from_comparison("in [[1, 2], [3]]")).to eql(["in", [[1, 2], [3]]])
        # Commas and brackets inside a quoted element do not split it
        expect(extract_operator_and_operand_from_comparison(%q(in ['a,b', '[c]']))).to eql(["in", ["a,b", "[c]"]])
      end

      it "should allow a trailing comma like a Ruby or Python list literal" do
        expect(extract_operator_and_operand_from_comparison("in [1,]")).to eql(["in", [1]])
      end

      it "should reject malformed lists" do
        expect { extract_operator_and_operand_from_comparison("in [1,,2]") }.to raise_error(/ERROR: Unable to parse operand/)
        expect { extract_operator_and_operand_from_comparison("in [,1]") }.to raise_error(/ERROR: Unable to parse operand/)
        expect { extract_operator_and_operand_from_comparison("in [1, 2]]") }.to raise_error(/ERROR: Unable to parse operand/)
        expect { extract_operator_and_operand_from_comparison(%q(in ['unterminated])) }.to raise_error(/ERROR: Unable to parse operand/)
      end

      it "should allow underscore separators in an exponent" do
        expect(extract_operator_and_operand_from_comparison("== 1e1_0")).to eql(["==", 1e10])
      end

      it "should require a list operand for the in operator" do
        expect { extract_operator_and_operand_from_comparison("in 'abc'") }.to \
          raise_error(/ERROR: The 'in' operator requires a list operand/)
        expect { extract_operator_and_operand_from_comparison("in 5") }.to \
          raise_error(/ERROR: The 'in' operator requires a list operand/)
      end
    end

    describe "compare_values" do
      it "should compare with all the supported operators" do
        expect(compare_values(1, "==", 1)).to be true
        expect(compare_values(1, "!=", 1)).to be false
        expect(compare_values(2, ">", 1)).to be true
        expect(compare_values(1, ">=", 1)).to be true
        expect(compare_values(1, "<", 2)).to be true
        expect(compare_values(1, "<=", 1)).to be true
        expect(compare_values(2, "in", [1, 2, 3])).to be true
        expect(compare_values(4, "in", [1, 2, 3])).to be false
      end

      it "should return false when the types can not be compared" do
        expect(compare_values(nil, ">", 1)).to be false
        expect(compare_values(1, ">", nil)).to be false
        expect(compare_values("STRING", ">", 1)).to be false
        # 'in' is containment against a list, matching Python, so a String operand is not a match
        expect(compare_values(1, "in", 1)).to be false
        expect(compare_values("a", "in", "abc")).to be false
      end

      it "should complain about invalid operators" do
        expect { compare_values(1, "&", 1) }.to raise_error(/ERROR: Invalid operator: '&'/)
      end
    end
  end
end
