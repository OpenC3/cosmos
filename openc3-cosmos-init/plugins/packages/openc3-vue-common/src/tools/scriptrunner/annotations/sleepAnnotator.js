/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.
*/

import RegexAnnotator from './regexAnnotator.js'

export default class SleepAnnotator extends RegexAnnotator {
  constructor(editor) {
    const prefix = '(^|[{\\s])' // Allowable characters before the keyword: start of line or { or a space
    const keyword = 'sleep' // The keyword this annotation looks for
    const suffix = '[\\(\\s]' // Allowable characters after the keyword: ( or a space
    super(editor, {
      pattern: new RegExp(`${prefix}${keyword}${suffix}`),
      text: 'Use `wait` instead of `sleep` in OpenC3 scripts', // because we override wait to make it work better, but not sleep
      type: 'warning',
    })
  }
}
