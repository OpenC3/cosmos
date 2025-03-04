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

require 'irb'
require 'irb/ruby-lex'
require 'prism'

class RubyLexUtils
  # The keyword arrays were taken from minifyrb:
  # https://github.com/koic/minifyrb/blob/72043fa2e3b8f2d445dd6b00a5ecec3e7cb6afd8/lib/minifyrb/minifier.rb
  AFTER_SPACE_REQUIRED_KEYWORDS = %i(
    KEYWORD_ALIAS KEYWORD_AND KEYWORD_BEGIN KEYWORD_BREAK KEYWORD_CASE KEYWORD_CLASS KEYWORD_DEF KEYWORD_DO KEYWORD_ELSE
    KEYWORD_ELSIF KEYWORD_ENSURE KEYWORD_FOR KEYWORD_IF KEYWORD_IF_MODIFIER KEYWORD_IN KEYWORD_MODULE KEYWORD_NEXT
    KEYWORD_NOT KEYWORD_OR KEYWORD_REDO KEYWORD_RESCUE KEYWORD_RESCUE_MODIFIER KEYWORD_RETURN KEYWORD_SUPER KEYWORD_THEN
    KEYWORD_UNDEF KEYWORD_UNLESS KEYWORD_UNLESS_MODIFIER KEYWORD_UNTIL KEYWORD_UNTIL_MODIFIER KEYWORD_WHEN KEYWORD_WHILE
    KEYWORD_WHILE_MODIFIER KEYWORD_YIELD
  )
  BEFORE_SPACE_REQUIRED_KEYWORDS = %i(
    KEYWORD_AND KEYWORD_DO KEYWORD_IF_MODIFIER KEYWORD_IN KEYWORD_OR KEYWORD_RESCUE_MODIFIER KEYWORD_THEN
    KEYWORD_UNLESS_MODIFIER KEYWORD_UNTIL_MODIFIER KEYWORD_WHILE_MODIFIER
  )
  REQUIRE_SPACE_AFTER_IDENTIFIER_TYPES = %i(IDENTIFIER KEYWORD_DO STRING_BEGIN) # KEYWORD_SELF KEYWORD_TRUE KEYWORD_FALSE KEYWORD_NIL METHOD_NAME) + NUMERIC_LITERAL_TYPES
  OPENING_DELIMITER_TYPES = %i(PARENTHESIS_LEFT BRACKET_LEFT BRACE_LEFT BRACKET_LEFT_ARRAY)
  CLOSING_DELIMITER_TYPES = %i(PARENTHESIS_RIGHT BRACKET_RIGHT BRACE_RIGHT BRACKET_RIGHT_ARRAY)

  UNINSTRUMENTABLE_KEYWORDS = %i(
    KEYWORD_CLASS KEYWORD_MODULE KEYWORD_DEF KEYWORD_UNDEF KEYWORD_BEGIN KEYWORD_RESCUE
    KEYWORD_ENSURE KEYWORD_END KEYWORD_IF KEYWORD_IF_MODIFIER KEYWORD_UNLESS KEYWORD_UNLESS_MODIFIER
    KEYWORD_THEN KEYWORD_ELSIF KEYWORD_ELSE KEYWORD_CASE KEYWORD_WHEN BRACE_LEFT
    KEYWORD_WHILE KEYWORD_UNTIL KEYWORD_UNTIL_MODIFIER KEYWORD_FOR KEYWORD_BREAK KEYWORD_NEXT
    KEYWORD_REDO KEYWORD_RETRY KEYWORD_IN KEYWORD_DO KEYWORD_RETURN KEYWORD_ALIAS
  )

  KEY_KEYWORDS = [
    'class'.freeze,
    'module'.freeze,
    'def'.freeze,
    'undef'.freeze,
    'begin'.freeze,
    'rescue'.freeze,
    'ensure'.freeze,
    'end'.freeze,
    'if'.freeze,
    'unless'.freeze,
    'then'.freeze,
    'elsif'.freeze,
    'else'.freeze,
    'case'.freeze,
    'when'.freeze,
    'while'.freeze,
    'until'.freeze,
    'for'.freeze,
    'break'.freeze,
    'next'.freeze,
    'redo'.freeze,
    'retry'.freeze,
    'in'.freeze,
    'do'.freeze,
    'return'.freeze,
    'alias'.freeze
  ]

  # @param text [String]
  # @return [Boolean] Whether the text contains a Ruby keyword
  def contains_keyword?(text)
    lex = Prism.lex(text)
    tokens = lex.value
    tokens.each do |token|
      token_object = token[0]
      state_bits = token[1]
      if token_object.type.start_with?("KEYWORD")
        if KEY_KEYWORDS.include?(token_object.value)
          return true
        end
      else
        if token_object.type == :BRACE_LEFT and state_bits != (Ripper::EXPR_BEG | Ripper::EXPR_LABEL)
          return true
        end
      end
    end
    return false
  end

  # @param text [String]
  # @param progress_dialog [OpenC3::ProgressDialog] If this is set, the overall
  #   progress will be set as the processing progresses
  # @return [String] The text with all comments removed
  def remove_comments(text, progress_dialog = nil)
    lex = Prism.lex(text)
    tokens = lex.value
    comments_removed = ""
    token_count = 0
    progress = 0.0
    tokens.each do |token|
      token_object = token[0]
      token_count += 1
      if token_object.type != :COMMENT
        comments_removed << token_object.value
      else
        newline_count = token_object.value.count("\n")
        comments_removed << ("\n" * newline_count)
      end
      if progress_dialog and token_count % 10000 == 0
        progress += 0.01
        progress = 0.0 if progress >= 0.99
        progress_dialog.set_overall_progress(progress)
      end
    end
    return comments_removed
  end

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
    # Attempt at using a flag to determine if a line is instrumentable
    # instrumentable = true
    tokens = Prism.lex(text).value
    tokens.each_cons(2) do |(token, _lex_state), (next_token, _next_lex_state)|
      # pp token
      # Ensure we have a space before the token if it's required
      line += ' ' if BEFORE_SPACE_REQUIRED_KEYWORDS.include?(token.type)
      line += token.value
      line_no ||= token.location.start_line
      orig_line_no ||= line_no

      # Thought about using this to determine if a line is instrumentable
      # but we're failing existing tests due to braces. Braces in the old
      # parser are context specific but in Prism they are just BRACE_LEFT and BRACE_RIGHT.
      # For now we'll just use the existing Ripper logic.
      # if UNINSTRUMENTABLE_KEYWORDS.include?(token.type)
      #   instrumentable = false
      # end
      case token.type
      when :EOF
        break
      when :IDENTIFIER
        if REQUIRE_SPACE_AFTER_IDENTIFIER_TYPES.include?(next_token.type)
          line += ' '
        end
      when :STRING_BEGIN
        string_begin = true
        line_no = token.location.start_line
      when :STRING_CONTENT
        next
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

      # Ensure we have a space after the token if it's required
      line += ' ' if AFTER_SPACE_REQUIRED_KEYWORDS.include?(token.type)
      # Don't process the line yet if we're waiting for additional tokens
      next if string_begin or waiting_on_newline or waiting_on_close > 0

      # This is where we process the line and yield it
      if line_no != token.location.start_line or line_no != token.location.end_line
        if contains_keyword?(line)
          yield line, false, inside_begin, orig_line_no
        elsif !line.empty?
          yield line, true, inside_begin, orig_line_no
        end
        line = ''
        orig_line_no = nil
        line_no = nil
      end
      prev_token = token
    end
  end
end
