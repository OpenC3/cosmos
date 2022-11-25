/*
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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

export class ConfigParserError {
  constructor(config_parser, message, usage = '', url = '') {
    this.keyword = config_parser.keyword
    this.parameters = config_parser.parameters
    this.filename = config_parser.filename
    this.line = config_parser.line
    this.lineNumber = config_parser.lineNumber
    this.message = message
    this.usage = usage
    this.url = url
  }
}

export class ConfigParserService {
  keyword = null
  parameters = []
  filename = ''
  line = ''
  lineNumber = 0
  url = 'https://openc3.com/docs/v5'

  constructor() {}

  verify_num_parameters(min_num_params, max_num_params, usage = '') {
    // This syntax works with 0 because each doesn't return any values
    // for a backwards range
    for (let index = 1; index <= min_num_params; index++) {
      // If the parameter is nil (0 based) then we have a problem
      if (this.parameters[index - 1] === undefined) {
        throw new ConfigParserError(
          this,
          `Not enough parameters for ${this.keyword}.`,
          usage,
          this.url
        )
      }
    }
    // If they pass null for max_params we don't check for a maximum number
    if (max_num_params && !this.parameters[max_num_params] === undefined) {
      throw new ConfigParserError(
        this,
        `Too many parameters for ${this.keyword}.`,
        usage,
        this.url
      )
    }
  }

  remove_quotes(string) {
    if (string.length < 2) {
      return string
    }
    let first_char = string.charAt(0)
    if (first_char !== '"' && first_char !== "'") {
      return string
    }
    let last_char = string.charAt(string.length - 1)
    if (first_char !== last_char) {
      return string
    }
    return string.substring(1, string.length - 1)
  }

  scan_string(string, rx) {
    if (!rx.global) throw "rx must have 'global' flag set"
    let r = []
    string.replace(rx, function (match) {
      r.push(match)
      return match
    })
    return r
  }

  parse_string(
    input_string,
    original_filename,
    yield_non_keyword_lines,
    remove_quotes,
    handler
  ) {
    let string_concat = false
    this.line = ''
    this.keyword = null
    this.parameters = []
    this.filename = original_filename

    // Break string into lines
    let lines = input_string.split('\n')
    let numLines = lines.length

    for (let i = 0; i < numLines; i++) {
      this.lineNumber = i + 1
      let line = lines[i].trim()

      if (string_concat === true) {
        // Skip comment lines after a string concatenation
        if (line[0] === '#') {
          continue
        }
        // Remove the opening quote if we're continuing the line
        line = line.substring(1, line.length)
      }

      // Check for string continuation
      let last_char = line.charAt(line.length - 1)
      switch (last_char) {
        case '+': // String concatenation with newlines
          this.line += '\n'
        // Deliberate fall through
        case '\\': // String concatenation
          // Trim off the concat character plus any spaces, e.g. "line" \
          let trim = line.substring(0, line.length - 1).trim()
          // Now trim off the last quote so it will flow into the next line
          this.line += trim.substring(0, trim.length - 1)
          string_concat = true
          continue
        case '&': // Line continuation
          this.line += line.substring(0, line.length - 1)
          continue
        default:
          this.line += line
      }
      string_concat = false
      console.log(this.line)

      let rx = /("([^\\"]|\\.)*")|('([^\\']|\\.)*')|\S+/g
      let data = this.scan_string(this.line, rx)
      let first_item = ''
      if (data.length > 0) {
        first_item = first_item + data[0]
      }

      if (first_item.length === 0 || first_item.charAt(0) === '#') {
        this.keyword = null
      } else {
        this.keyword = first_item.toUpperCase()
      }
      this.parameters = []

      // Ignore lines without keywords: comments and blank lines
      if (this.keyword === null) {
        if (yield_non_keyword_lines) {
          handler(this.keyword, this.parameters, this.line, this.lineNumber)
        }
        this.line = ''
        continue
      }

      let length = data.length
      if (length > 1) {
        for (let index = 1; index < length; index++) {
          let string = data[index]

          // Don't process trailing comments such as:
          // KEYWORD PARAM #This is a comment
          if (string.length > 0 && string.charAt(0) === '#') {
            break
          }
          if (remove_quotes) {
            this.parameters.push(this.remove_quotes(string))
          } else {
            this.parameters.push(string)
          }
        }
      }
      handler(this.keyword, this.parameters, this.line, this.lineNumber)
      this.line = ''
    } // for all the lines
  } // parse_string
} // class ConfigParserService
