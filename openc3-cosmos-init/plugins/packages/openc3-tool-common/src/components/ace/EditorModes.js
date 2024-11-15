/*
# Copyright 2024 OpenC3, Inc.
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
*/

import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/mode-python'
import 'ace-builds/src-min-noconflict/mode-json'
import 'ace-builds/src-min-noconflict/mode-markdown'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'

export default {
  data: {
    configKey: '',
  },
  methods: {
    buildLanguageMode(HighlightRules, FoldMode) {
      let oop = ace.require('ace/lib/oop')
      let apis = Object.getOwnPropertyNames(OpenC3Api.prototype)
        .filter((a) => a !== 'constructor')
        .filter((a) => a !== 'exec')
        // Add the Public apis in api_shared but not in OpenC3Api
        .concat([
          'check',
          'check_raw',
          'check_formatted',
          'check_with_units',
          'check_exception',
          'check_tolerance',
          'check_expression',
          'wait',
          'wait_tolerance',
          'wait_expression',
          'wait_check',
          'wait_check_tolerance',
          'wait_check_expression',
          'wait_packet',
          'wait_check_packet',
          'disable_instrumentation',
          'set_line_delay',
          'get_line_delay',
          'set_max_output',
          'get_max_output',
        ])
      let regex = new RegExp(`(\\b${apis.join('\\b|\\b')}\\b)`)
      let OpenC3HighlightRules = function () {
        HighlightRules.call(this)
        // add openc3 rules to the rules
        for (let rule in this.$rules) {
          this.$rules[rule].unshift({
            regex: regex,
            token: 'support.function',
          })
        }
      }
      oop.inherits(OpenC3HighlightRules, HighlightRules)

      let MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent',
      ).MatchingBraceOutdent
      let CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle',
      ).CstyleBehaviour
      let Mode = function () {
        this.HighlightRules = OpenC3HighlightRules
        this.$outdent = new MatchingBraceOutdent()
        this.$behaviour = new CstyleBehaviour()
        this.foldingRules = new FoldMode()
        this.indentKeywords = this.foldingRules.indentKeywords
      }
      return [oop, Mode]
    },
    buildRubyMode() {
      const [oop, Mode] = this.buildLanguageMode(
        ace.require('ace/mode/ruby_highlight_rules').RubyHighlightRules,
        ace.require('ace/mode/folding/ruby').FoldMode,
      )
      let RubyMode = ace.require('ace/mode/ruby').Mode
      oop.inherits(Mode, RubyMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
    },
    buildPythonMode() {
      const [oop, Mode] = this.buildLanguageMode(
        ace.require('ace/mode/python_highlight_rules').PythonHighlightRules,
        ace.require('ace/mode/folding/pythonic').FoldMode,
      )
      let PythonMode = ace.require('ace/mode/python').Mode
      oop.inherits(Mode, PythonMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
    },
    buildJsonMode() {
      const [oop, Mode] = this.buildLanguageMode(
        ace.require('ace/mode/json_highlight_rules').JsonHighlightRules,
        ace.require('ace/mode/folding/ruby').FoldMode,
      )
      let JsonMode = ace.require('ace/mode/json').Mode
      oop.inherits(Mode, JsonMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
    },
    buildMarkdownMode() {
      const [oop, Mode] = this.buildLanguageMode(
        ace.require('ace/mode/markdown_highlight_rules').MarkdownHighlightRules,
        ace.require('ace/mode/folding/markdown').FoldMode,
      )
      let MarkdownMode = ace.require('ace/mode/markdown').Mode
      oop.inherits(Mode, MarkdownMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
    },
  },
}
