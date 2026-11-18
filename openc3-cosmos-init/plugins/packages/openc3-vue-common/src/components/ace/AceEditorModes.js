/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/mode-python'
import 'ace-builds/src-min-noconflict/mode-json'
import 'ace-builds/src-min-noconflict/mode-markdown'
import { OpenC3Api } from '@openc3/js-common/services'

// Builds a mode class: the stock language mode plus highlighting for the
// OpenC3 API method names
function buildLanguageMode(HighlightRules, FoldMode) {
  let oop = ace.require('ace/lib/oop')
  let apis = Object.getOwnPropertyNames(OpenC3Api.prototype)
    .filter((a) => a !== 'constructor')
    .filter((a) => a !== 'exec')
    // Add the Public apis in api_shared but not in OpenC3Api
    .concat([
      'check',
      'check_raw',
      'check_formatted',
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
  let CstyleBehaviour = ace.require('ace/mode/behaviour/cstyle').CstyleBehaviour
  let Mode = function () {
    this.HighlightRules = OpenC3HighlightRules
    this.$outdent = new MatchingBraceOutdent()
    this.$behaviour = new CstyleBehaviour()
    this.foldingRules = new FoldMode()
    this.indentKeywords = this.foldingRules.indentKeywords
  }
  return [oop, Mode]
}

// Returns a mode class (not an instance), as the mixin methods always have
function buildModeClass(highlightRules, foldMode, baseMode) {
  const [oop, Mode] = buildLanguageMode(
    ace.require(highlightRules[0])[highlightRules[1]],
    ace.require(foldMode).FoldMode,
  )
  oop.inherits(Mode, ace.require(baseMode).Mode)
  ;(function () {
    this.$id = 'ace/mode/openc3'
  }).call(Mode.prototype)
  return Mode
}

const BUILDERS = {
  ruby: () =>
    buildModeClass(
      ['ace/mode/ruby_highlight_rules', 'RubyHighlightRules'],
      'ace/mode/folding/ruby',
      'ace/mode/ruby',
    ),
  python: () =>
    buildModeClass(
      ['ace/mode/python_highlight_rules', 'PythonHighlightRules'],
      'ace/mode/folding/pythonic',
      'ace/mode/python',
    ),
  json: () =>
    buildModeClass(
      ['ace/mode/json_highlight_rules', 'JsonHighlightRules'],
      'ace/mode/folding/ruby',
      'ace/mode/json',
    ),
  markdown: () =>
    buildModeClass(
      ['ace/mode/markdown_highlight_rules', 'MarkdownHighlightRules'],
      'ace/mode/folding/markdown',
      'ace/mode/markdown',
    ),
}

// Built on first use and shared by every editor that uses a mode name
const instances = {}

// The shared OpenC3 mode instance for 'ruby', 'python', 'json' or 'markdown'.
// AceEditor uses this to resolve its `mode` prop.
export function getOpenC3Mode(name) {
  if (!BUILDERS[name]) {
    throw new Error(`Unknown OpenC3 Ace mode: ${name}`)
  }
  instances[name] ??= new (BUILDERS[name]())()
  return instances[name]
}

// Mixin for components that build their own mode instances. Each build method
// returns a new mode class: `new (this.buildRubyMode())()`. Prefer passing a
// mode name to AceEditor's `mode` prop instead.
export default {
  methods: {
    buildLanguageMode,
    buildRubyMode: BUILDERS.ruby,
    buildPythonMode: BUILDERS.python,
    buildJsonMode: BUILDERS.json,
    buildMarkdownMode: BUILDERS.markdown,
  },
}
