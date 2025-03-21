# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'irb/ruby-lex'
require 'prism'

class RubyLexUtils
  OPENING_DELIMITER_TYPES = %i(PARENTHESIS_LEFT BRACKET_LEFT BRACE_LEFT BRACKET_LEFT_ARRAY)
  CLOSING_DELIMITER_TYPES = %i(PARENTHESIS_RIGHT BRACKET_RIGHT BRACE_RIGHT BRACKET_RIGHT_ARRAY)

  UNINSTRUMENTABLE_KEYWORDS = %i(
    KEYWORD_CLASS KEYWORD_MODULE KEYWORD_DEF KEYWORD_UNDEF KEYWORD_BEGIN KEYWORD_RESCUE
    KEYWORD_ENSURE KEYWORD_END KEYWORD_IF KEYWORD_IF_MODIFIER KEYWORD_UNLESS KEYWORD_UNLESS_MODIFIER
    KEYWORD_THEN KEYWORD_ELSIF KEYWORD_ELSE KEYWORD_CASE KEYWORD_WHEN
    KEYWORD_WHILE KEYWORD_UNTIL KEYWORD_UNTIL_MODIFIER KEYWORD_FOR KEYWORD_BREAK KEYWORD_NEXT
    KEYWORD_REDO KEYWORD_RETRY KEYWORD_IN KEYWORD_DO KEYWORD_RETURN KEYWORD_ALIAS
  )

  # Yields each lexed segment and if the segment is instrumentable
  #
  # @param text [String]
  # @yieldparam line [String] The entire line
  # @yieldparam instrumentable [Boolean] Whether the line is instrumentable
  # @yieldparam inside_begin [Integer] The level of indentation
  # @yieldparam line_no [Integer] The current line number
  def each_lexed_segment(text)
    line = ''
    begin_indent = nil
    inside_begin = false
    string_begin = false
    orig_line_no = nil
    line_no = nil
    rescue_line_no = nil
    waiting_on_newline = false
    waiting_on_close = 0
    prev_token = nil
    instrumentable = true
    tokens = Prism.lex(text).value
    # See: https://github.com/ruby/prism/blob/main/lib/prism/parse_result.rb
    # for what is returned by Prism.lex
    # We process the tokens in pairs to recreate spacing and handle string assignments
    tokens.each_cons(2) do |(token, lex_state), (next_token, _next_lex_state)|
      # pp token # Uncomment for debugging
      # Ignore embedded documentation must be at column 0 and looks like:
=begin
This is a comment
And so is this
=end
      if token.type == :EMBDOC_BEGIN or token.type == :EMBDOC_LINE or token.type == :EMBDOC_END
        prev_token = token
        next
      end

      # Recreate the spaces at the beginning of a line
      # This has to come before we add the token.value to the line
      if prev_token.nil?
        line += ' ' * token.location.start_column
      # If the previous token is STRING_CONTENT it is probably string interpolation so ignore it
      # Otherwise if the previous token has changed lines we're on a newline so add space
      elsif prev_token.type != :STRING_CONTENT and prev_token.location.end_line - prev_token.location.start_line > 0
        line += ' ' * token.location.start_column
      end
      prev_token = token

      # Comments require tacking on a newline but are otherwise ignored
      if token.type == :COMMENT
        line += "\n"
        waiting_on_newline = false
      else
        line += token.value
      end

      if UNINSTRUMENTABLE_KEYWORDS.include?(token.type)
        instrumentable = false
      end

      # We're processing tokens in pairs so we need to check if we're at the end
      # of the file and process the last line
      if next_token.type == :EOF
        if !line.empty?
          yield line, instrumentable, inside_begin, orig_line_no
        end
        break
      end

      # Recreate spaces between tokens rather than trying to figure out
      # which tokens require spacing before and after
      if token.location.start_line == next_token.location.start_line
        spaces = next_token.location.start_column - token.location.end_column
        line += ' ' * spaces
      end
      line_no ||= token.location.start_line
      # Keep track of the original line number because the line number can change
      # when we're putting together multiline structures like strings, arrays, hashes, etc.
      orig_line_no ||= line_no

      case token.type
      when :BRACE_LEFT
        # BRACE is a special case because it can be used for hashes and blocks
        if lex_state != (Ripper::EXPR_BEG | Ripper::EXPR_LABEL)
          instrumentable = false
        end
        waiting_on_close += 1
      when :STRING_BEGIN
        # Mark when a string begins to allow for processing string interpolation tokens
        string_begin = true
        line_no = token.location.start_line
      when :STRING_END
        string_begin = false
        next
      when :KEYWORD_BEGIN
        inside_begin = true
        begin_indent = token.location.start_column unless begin_indent # Don't restart for nested begins
      when :KEYWORD_RESCUE
        rescue_line_no = token.location.start_line
      when :KEYWORD_END
        # Assume the begin and end are aligned
        # Otherwise we have to count any keywords that can close with END
        if token.location.start_line == rescue_line_no || token.location.start_column == begin_indent
          inside_begin = false
        end
      when *OPENING_DELIMITER_TYPES
        waiting_on_close += 1
      when *CLOSING_DELIMITER_TYPES
        waiting_on_close -= 1
        waiting_on_newline = true
      when :NEWLINE, :IGNORED_NEWLINE
        waiting_on_newline = false
        # If the next token is a STRING_BEGIN then hold off processing the newline
        # because it's going to be a string assignment
        next if next_token.type == :STRING_BEGIN
      end

      # Don't process the line yet if we're waiting for additional tokens
      next if string_begin or waiting_on_newline or waiting_on_close > 0

      # This is where we process the line and yield it
      if line_no != token.location.start_line or line_no != token.location.end_line
        yield line, instrumentable, inside_begin, orig_line_no
        line = ''
        instrumentable = true
        orig_line_no = nil
        line_no = nil
      end
    end
  end
end
