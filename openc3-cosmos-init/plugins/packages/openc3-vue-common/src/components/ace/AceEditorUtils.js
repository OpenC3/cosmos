/*
# Copyright 2025, OpenC3, Inc.
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
*/

import 'ace-builds/src-min-noconflict/keybinding-vim'
import 'ace-builds/src-min-noconflict/ext-searchbox'

const VIM_MODE_STORAGE_KEY = 'openc3-ace-vim-mode-enabled'
const VIM_KEYBOARD_HANDLER = 'ace/keyboard/vim'
const DEFAULT_LANGUAGE_STORAGE_KEY = 'openc3-ace-default-scripting-language'

export default {
  /**
   * Check if vim mode is enabled from localStorage
   * @returns {boolean} true if vim mode is enabled
   */
  isVimModeEnabled() {
    return localStorage.getItem(VIM_MODE_STORAGE_KEY) === 'true'
  },

  /**
   * Sets the vim mode setting in localStorage
   * @param {boolean} value - new vim mode state
   */
  setVimMode(value) {
    localStorage.setItem(VIM_MODE_STORAGE_KEY, JSON.stringify(!!value))
  },

  /**
   * Toggle vim mode on/off and save to localStorage
   * @param {Object} editor - Ace editor instance
   */
  toggleVimMode(editor) {
    const isEnabled = this.isVimModeEnabled()

    if (isEnabled) {
      // Disable vim mode
      editor.setKeyboardHandler(null)
      this.setVimMode(false)
    } else {
      // Enable vim mode
      editor.setKeyboardHandler(VIM_KEYBOARD_HANDLER)
      this.setVimMode(true)
    }
    editor.focus()
  },

  /**
   * Apply vim mode to editor if enabled in localStorage
   * @param {Object} editor - Ace editor instance
   */
  applyVimModeIfEnabled(editor, { saveFn } = {}) {
    if (this.isVimModeEnabled()) {
      editor.setKeyboardHandler(VIM_KEYBOARD_HANDLER)
      ace.config.loadModule(VIM_KEYBOARD_HANDLER, (module) => {
        module.CodeMirror.Vim.defineEx('write', 'w', (codeMirror) => {
          if (typeof saveFn === 'function') {
            saveFn()
          } else {
            codeMirror.ace.execCommand('save')
          }
        })
      })
    } else {
      editor.setKeyboardHandler(null)
    }
  },

  /**
   * Get the default scripting language from localStorage
   * @returns {string} 'ruby' or 'python', defaults to 'python'
   */
  getDefaultScriptingLanguage() {
    return localStorage.getItem(DEFAULT_LANGUAGE_STORAGE_KEY) || 'python'
  },

  /**
   * Set the default scripting language in localStorage
   * @param {string} language - 'ruby' or 'python'
   */
  setDefaultScriptingLanguage(language) {
    if (language === 'ruby' || language === 'python') {
      localStorage.setItem(DEFAULT_LANGUAGE_STORAGE_KEY, language)
    }
  },
}
