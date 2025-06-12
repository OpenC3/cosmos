# Copyright 2025 OpenC3, Inc.
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

import re

class ScriptEngine:
    def __init__(self, running_script):
        self.running_script = running_script

    # Override this method in the subclass to implement the script engine
    def run_line(self, line, lines, filename, line_no):
        print(line)
        return line_no + 1

    def run_text(self, text, filename = None, line_no = 1, end_line_no = None, bind_variables = False):
        lines = text.splitlines()

        while True:
            if line_no > len(lines):
                return
            line = lines[line_no - 1]
            next_line_no = line_no + 1

            while True:
                try:
                    self.running_script.pre_line_instrumentation(filename, line_no, globals(), locals())
                    next_line_no = self.run_line(line, lines, filename, line_no)
                    break
                except Exception as e:
                    retry_needed = self.running_script.exception_instrumentation(filename, line_no)
                    if retry_needed:
                        continue
                    else:
                        break
                finally:
                    self.running_script.post_line_instrumentation(filename, line_no)

            line_no = next_line_no
            if end_line_no and line_no > end_line_no:
                return

    def debug(self, text):
        self.run_line(text, [text], "DEBUG", 1)

    def syntax_check(self, text, filename = None):
        print("Not Implemented")
        return 1

    def mnemonic_check(self, text, filename = None):
        print("Not Implemented")
        return 1

    def tokenizer(self, s, special_chars='()><+-*/=;,'):
        """
        Advanced tokenizer that:
        1. Preserves quoted strings with their quotes
        2. Separates specified special characters as individual tokens

        Args:
            s: Input string
            special_chars: String of characters to separate
        """
        # Escape special characters for the regex pattern
        escaped_chars = re.escape(special_chars)

        result = []
        i = 0
        while i < len(s):
            # Skip whitespace
            if s[i].isspace():
                i += 1
                continue

            # Handle quoted strings (single or double quotes)
            if s[i] in ['"', "'"]:
                quote_char = s[i]
                quote_start = i
                i += 1
                # Find the closing quote
                while i < len(s):
                    if s[i] == '\\' and i + 1 < len(s):  # Handle escaped characters
                        i += 2
                    elif s[i] == quote_char:  # Found closing quote
                        i += 1
                        break
                    else:
                        i += 1
                # Include the quotes in the token
                result.append(s[quote_start:i])
                continue

            # Handle special characters
            if s[i] in special_chars:
                result.append(s[i])
                i += 1
                continue

            # Handle regular tokens
            token_start = i
            while i < len(s) and not s[i].isspace() and s[i] not in special_chars and s[i] not in ['"', "'"]:
                i += 1
            if i > token_start:
                result.append(s[token_start:i])

        return result
