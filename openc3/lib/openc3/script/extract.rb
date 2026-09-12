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

require 'json'
require 'openc3/utilities/store'

module OpenC3
  module Extract
    # Tokenizer for command parameters: matches double quoted strings, single quoted strings,
    # bracket delimited arrays (one level of nesting), a bare comma delimiter, or bare words
    # (runs of non-whitespace, non-comma characters). Commas are tokenized separately so
    # whitespace around them is optional.
    SCANNING_REGULAR_EXPRESSION = %r{ (?:"(?:[^\\"]|\\.)*") | (?:'(?:[^\\']|\\.)*') | (?:\[(?:[^\\\[\]]|\\.|\[(?:[^\\\[\]]|\\.)*\])*\]) | , | [^\s,]+ }x # "

    # Operators supported by check(), wait() and wait_check() comparisons
    COMPARISON_OPERATORS = ["==", "!=", ">=", "<=", ">", "<", "in"]

    # Single character escape sequences processed inside a double quoted comparison operand.
    # The numeric (\nnn, \xHH, \uHHHH, \u{...}) forms are handled by unescape_double_quoted().
    DOUBLE_QUOTE_ESCAPES = {
      '\\' => "\\", '"' => '"', "'" => "'", '#' => '#', 'n' => "\n", 't' => "\t",
      'r' => "\r", 'a' => "\a", 'b' => "\b", 'e' => "\e", 'f' => "\f", 'v' => "\v", 's' => ' '
    }

    # Tokenizes a double quoted operand into escape sequences, interpolation markers and runs
    # of plain characters. The alternatives are ordered longest first so \u{1F600} is not read
    # as \u, and the escape alternatives precede the markers so \#{ is a literal '#{'.
    DOUBLE_QUOTE_TOKEN_REGEX =
      /\\u\{[\h\s]*\}|\\u\h{4}|\\x\h{1,2}|\\[0-7]{1,3}|\\M-\\C-.|\\M-.|\\C-.|\\c.|\\.|\#[{@$]|[^\\\#]+|\#/m

    # Escape sequences which have a meaning we deliberately do not implement. Dropping the
    # backslash would silently change the value so they are rejected instead.
    UNSUPPORTED_ESCAPE_REGEX = /\A\\(?:c|C-|M-)/

    # The Ruby string interpolation markers. Interpolation would be code execution so it is
    # rejected rather than silently compared against the uninterpolated text.
    INTERPOLATION_REGEX = /\A\#[{@$]/

    # Limits Ruby enforces on a \u escape. A codepoint is written with at most six hex digits,
    # the largest character Unicode defines is 0x10FFFF, and the surrogate range is reserved
    # for UTF-16 pairs so it is not a character on its own.
    MAX_UNICODE_DIGITS = 6
    MAX_UNICODE_CODEPOINT = 0x10FFFF
    UNICODE_SURROGATE_RANGE = (0xD800..0xDFFF)

    private

    # Pulls all string keyword arguments into the args array. Raises on any symbol keyword arguments.
    # Thus this method should only be called after you already filter out any symbol keyword arguments.
    def extract_string_kwargs_to_args(args, kwargs)
      # Split keywords into string keywords (part of our API, e.g. "PARAM" => 123) and
      # symbol keywords which are meant for the internal methods, e.g. scope:, token:, timeout:
      # If the user tries to pass symbol keywords then that is an error
      str, sym = kwargs.partition {|k, _v| k.is_a?(String) }.map(&:to_h)
      # We use :manual in all our APIs so we remove it from the check
      sym.delete(:manual)
      unless sym.empty?
        raise ArgumentError, "Unknown symbol keyword(s): #{sym.keys.join(', ')}. "\
          "COSMOS command parameters must be passed as strings: \"#{sym.to_a[0][0]}\" => ..."
      end
      args << str unless str.empty?
    end

    def add_cmd_parameter(keyword, value, packet, cmd_params)
      quotes_removed = value.remove_quotes
      if value == quotes_removed
        type = nil
        if packet['items']
          packet['items'].each do |parameter|
            if parameter['name'] == keyword
              type = parameter['data_type']
              break
            end
          end
        end
        if (type == 'STRING' or type == 'BLOCK') and value.upcase.start_with?("0X")
          cmd_params[keyword] = value.hex_to_byte_string
        else
          cmd_params[keyword] = value.convert_to_value
        end
      else
        cmd_params[keyword] = quotes_removed
      end
    end

    def extract_fields_from_cmd_text(text, scope: $openc3_scope)
      split_string = text.split(/\s+with\s+/i, 2)
      raise "ERROR: text must not be empty" if split_string.length == 0
      raise "ERROR: 'with' must be followed by parameters : #{text}" if (split_string.length == 1 and text =~ /\s*with\s*/i) or (split_string.length == 2 and split_string[1].empty?)

      # Extract target_name and cmd_name
      first_half = split_string[0].split
      raise "ERROR: Both Target Name and Command Name must be given : #{text}" if first_half.length < 2
      raise "ERROR: Only Target Name and Command Name must be given before 'with' : #{text}" if first_half.length > 2

      target_name = first_half[0]
      cmd_name = first_half[1]
      cmd_params = {}

      begin
        # Returns the packet JSON representation
        packet = TargetModel.packet(target_name, cmd_name, type: :CMD, scope: scope)
      rescue
        packet = {}
      end

      if split_string.length == 2
        # Extract Command Parameters
        second_half = split_string[1].scan(SCANNING_REGULAR_EXPRESSION)
        keyword = nil
        value = nil
        second_half.each do |item|
          if item == ','
            # A comma completes the current keyword / value pair.
            # A comma with nothing pending is a leading or duplicated comma.
            raise "Missing command parameter before comma: #{text}" unless keyword
            raise "Missing value for last command parameter: #{text}" unless value
            add_cmd_parameter(keyword, value, packet, cmd_params)
            keyword = nil
            value = nil
          elsif keyword.nil?
            keyword = item
          elsif value.nil?
            value = item
          else
            raise "Missing comma in command parameters: #{text}"
          end
        end
        if keyword
          raise "Missing value for last command parameter: #{text}" unless value
          add_cmd_parameter(keyword, value, packet, cmd_params)
        end
      end

      return [target_name, cmd_name, cmd_params]
    end

    def extract_fields_from_tlm_text(text)
      split_string = text.split
      raise "ERROR: Telemetry Item must be specified as 'TargetName PacketName ItemName' : #{text}" if split_string.length != 3

      target_name = split_string[0]
      packet_name = split_string[1]
      item_name = split_string[2]
      return [target_name, packet_name, item_name]
    end

    def extract_fields_from_set_tlm_text(text)
      error_msg = "ERROR: Set Telemetry Item must be specified as 'TargetName PacketName ItemName = Value' : #{text}"
      # We have to handle these cases:
      # set_tlm("TGT PKT ITEM='new item'")
      # set_tlm("TGT PKT ITEM = 'new item'")
      # set_tlm("TGT PKT ITEM= 'new item'")
      # set_tlm("TGT PKT ITEM ='new item'")
      split_string = text.split('=')
      raise error_msg if split_string.length < 2 || split_string[1].strip.empty?

      split_string = split_string[0].strip.split << split_string[1..-1].join('=').strip
      raise error_msg if split_string.length != 4 # Ensure tgt,pkt,item,value

      target_name = split_string[0]
      packet_name = split_string[1]
      item_name = split_string[2]
      value = split_string[3].strip.convert_to_value
      value = value.remove_quotes if String === value
      return [target_name, packet_name, item_name, value]
    end

    def extract_fields_from_check_text(text)
      target_name, packet_name, item_name, comparison = text.split(nil, 4) # Ruby: second split arg is max number of resultant elements
      raise "ERROR: Check improperly specified: #{text}" if item_name.nil?

      # comparison is either nil, the comparison string, or an empty string.
      # We need it to not be an empty string.
      comparison = nil if comparison&.length == 0

      operator, _ = comparison&.split(nil, 2)
      raise "ERROR: Use '==' instead of '=' in #{text}" if operator == "="

      return [target_name, packet_name, item_name, comparison]
    end

    # Splits `check()` comparison expressions, e.g. "== 'foo bar'" becomes ["==", "foo bar"]
    def extract_operator_and_operand_from_comparison(comparison)
      operator, operand = comparison.split(nil, 2) # Ruby: second split arg is max number of resultant elements

      if operand.nil?
        # Don't allow operator without operand
        raise "ERROR: Invalid comparison, must specify an operand: #{comparison}" if !operator.nil?
        return [nil, nil]
      end

      raise "ERROR: Invalid operator: '#{operator}'" unless COMPARISON_OPERATORS.include?(operator)

      operand = extract_operand(operand)
      # 'in' is containment against a list of values in both Ruby and Python.
      # Enforced here so check(), wait() and wait_check() all reject the same thing.
      if operator == "in" and !operand.is_a?(Array)
        raise "ERROR: The 'in' operator requires a list operand: #{operand.inspect}"
      end

      return [operator, operand]
    end

    # Converts the operand of a `check()` comparison expression into a Ruby value.
    # Note this deliberately does not eval the operand so only literal values are supported.
    def extract_operand(operand)
      # A quoted operand must be a single complete string literal. Anything trailing the
      # closing quote, e.g. "== 'a' garbage 'b'", is a syntax error rather than a string.
      if (match = operand.match(/\A'((?:[^'\\]|\\.)*)'\z/m))
        # Ruby single quoted strings only escape the backslash and the single quote
        return match[1].gsub(/\\([\\'])/) { $1 }
      end
      if (match = operand.match(/\A"((?:[^"\\]|\\.)*)"\z/m))
        return unescape_double_quoted(match[1])
      end
      return nil if operand == "nil"
      return false if operand == "false"
      return true if operand == "true"

      # Ruby's Float() rejects these but Python's float() accepts them
      case operand.upcase
      when 'INFINITY', '+INFINITY', 'INF', '+INF'
        return Float::INFINITY
      when '-INFINITY', '-INF'
        return -Float::INFINITY
      when 'NAN', '+NAN', '-NAN'
        return Float::NAN
      else
        # Not an infinity or NaN keyword so fall through to the formats below
      end

      # Arrays are parsed recursively so their elements follow exactly the same rules as a
      # bare operand. JSON alone would reject ['ON', 'OFF'], [0xA, 0xB] and [true, nil].
      if operand.start_with?('[') and operand.end_with?(']')
        return split_operand_list(operand[1..-2]).map { |element| extract_operand(element) }
      end
      # JSON handles decimal numbers and hashes
      begin
        return JSON.parse(operand)
      rescue JSON::ParserError
        # Fall through to the number formats JSON does not accept
      end
      # Number formats JSON does not accept
      begin
        # Explicit base prefix: hex (0x), octal (0o) or binary (0b)
        return Integer(operand) if operand.match?(/\A[+-]?0[xXoObB][0-9a-fA-F_]+\z/)
        # Integers with underscore separators, e.g. 1_000. A leading zero is deliberately
        # rejected because it is ambiguous: Ruby reads 010 as octal 8 while Python rejects it.
        # Write 0o10 for octal 8 or 10 for decimal 10.
        return Integer(operand, 10) if operand.match?(/\A[+-]?[1-9][0-9_]*\z/)
        # Floats with underscore separators, e.g. 1_000.5. A leading zero is unambiguous here.
        return Float(operand) if operand.match?(/\A[+-]?[0-9][0-9_]*(?:\.[0-9_]+(?:[eE][+-]?[0-9_]+)?|[eE][+-]?[0-9_]+)\z/)
      rescue ArgumentError
        # Fall through to the error cases
      end

      # A bare word is almost always a string the user forgot to quote
      if operand.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        raise NameError, "Uninitialized constant #{operand}. Did you mean '#{operand}' as a string?"
      end
      raise "ERROR: Unable to parse operand: #{operand}"
    end

    # Processes the escape sequences in the contents of a double quoted operand
    def unescape_double_quoted(string)
      # A \xHH or octal escape can produce a byte which is not valid UTF-8 so build the result
      # in binary. Otherwise preserve the encoding of the comparison the user passed in.
      binary = string.match?(/\\(?:x\h|[0-7])/)
      result = binary ? ''.b : String.new(encoding: string.encoding)
      string.scan(DOUBLE_QUOTE_TOKEN_REGEX).each do |token|
        replacement =
          if token.match?(INTERPOLATION_REGEX)
            raise "ERROR: String interpolation is not supported in an operand: #{token}. " +
                  'Interpolate in the script itself or escape it as \#' + token[1] +
                  ' to compare against the literal text'
          elsif !token.start_with?('\\')
            token
          elsif token.start_with?('\u{')
            # \u{1F600} or \u{48 49} which is one or more whitespace separated codepoints
            token[3..-2].split.map { |codepoint| pack_unicode_codepoint(codepoint, token) }.join
          elsif token.length == 6 and token.start_with?('\u')
            pack_unicode_codepoint(token[2..-1], token)
          elsif token.length > 2 and token.start_with?('\x')
            [token[2..-1].hex].pack('C')
          elsif token.match?(/\A\\[0-7]/)
            [token[1..-1].to_i(8) & 0xFF].pack('C')
          elsif token.match?(UNSUPPORTED_ESCAPE_REGEX)
            raise "ERROR: Unsupported escape sequence in operand: #{token}"
          elsif token == '\u' or token == '\x'
            raise "ERROR: Invalid escape sequence in operand: #{token}"
          else
            # Ruby drops the backslash of an escape which has no special meaning, e.g. "\q"
            DOUBLE_QUOTE_ESCAPES.fetch(token[1], token[1])
          end
        result << (binary ? replacement.b : replacement)
      end
      return result
    end

    # Packs a single codepoint of a \u escape into a UTF-8 character. Ruby rejects a codepoint
    # which is too long, above the largest Unicode character or in the UTF-16 surrogate range,
    # so those raise here rather than silently packing into an invalid UTF-8 string.
    def pack_unicode_codepoint(codepoint, token)
      value = codepoint.hex
      if codepoint.length > MAX_UNICODE_DIGITS or value > MAX_UNICODE_CODEPOINT or
         UNICODE_SURROGATE_RANGE.include?(value)
        raise "ERROR: Invalid Unicode codepoint in operand: #{token}"
      end
      return [value].pack('U')
    end

    # Splits the contents of a bracketed operand list on the top level commas.
    # Quotes and nesting are tracked so "['a,b', [1, 2]]" is two elements, not four.
    def split_operand_list(text)
      elements = []
      current = String.new(encoding: text.encoding)
      depth = 0
      quote = nil
      escaped = false
      text.each_char do |char|
        if escaped
          escaped = false
        elsif quote
          if char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
        elsif char == "'" or char == '"'
          quote = char
        elsif char == '[' or char == '{'
          depth += 1
        elsif char == ']' or char == '}'
          depth -= 1
          raise "ERROR: Unable to parse operand: [#{text}]" if depth < 0
        elsif char == ',' and depth == 0
          elements << current.strip
          current = String.new(encoding: text.encoding)
          next
        end
        current << char
      end
      raise "ERROR: Unable to parse operand: [#{text}]" if depth != 0 or quote

      elements << current.strip
      # A single empty element is an empty list, e.g. []
      return [] if elements.length == 1 and elements[0].empty?
      # A trailing comma is allowed, e.g. [1,], matching both Ruby and Python list literals
      elements.pop if elements[-1].empty?
      raise "ERROR: Unable to parse operand: [#{text}]" if elements.empty? or elements.any?(&:empty?)

      return elements
    end

    # Compares a telemetry value against an operand using the given operator.
    # Returns false rather than raising if the two values can not be compared.
    def compare_values(value, operator, operand)
      case operator
      when "=="
        value == operand
      when "!="
        value != operand
      when ">"
        value > operand
      when ">="
        value >= operand
      when "<"
        value < operand
      when "<="
        value <= operand
      when "in"
        # 'in' is containment against a list of values, matching Python
        operand.is_a?(Array) && operand.include?(value)
      else
        raise "ERROR: Invalid operator: '#{operator}'"
      end
    rescue ArgumentError, NoMethodError, TypeError
      # Comparing incompatible types, e.g. nil > 1, is simply not a match
      false
    end
  end
end
