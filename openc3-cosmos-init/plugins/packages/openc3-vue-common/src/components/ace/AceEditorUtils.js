/*
# Copyright 2025, OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/keybinding-vim'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import 'ace-builds/src-min-noconflict/theme-twilight'

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

  /**
   * Initialize an ACE editor with common settings
   * @param {HTMLElement} element - DOM element to attach editor to
   * @param {Object} options - Configuration options
   * @param {Object} options.mode - ACE mode instance (e.g., new RubyMode())
   * @param {string} options.theme - ACE theme name
   * @param {number} options.tabSize - Tab size in spaces
   * @param {boolean} options.wrapMode - Enable line wrapping
   * @param {boolean} options.highlightActiveLine - Highlight current line
   * @param {boolean} options.enableAutocompletion - Enable basic autocompletion
   * @param {boolean} options.enableLiveAutocompletion - Enable live autocompletion
   * @param {Array} options.completers - Array of completer objects
   * @param {boolean} options.readOnly - Make editor read-only
   * @param {boolean} options.hideCursor - Hide cursor in read-only mode
   * @param {string} options.value - Initial editor content
   * @param {Function} options.vimModeSaveFn - Save function for vim :w command
   * @param {Function} options.onChange - Change event handler
   * @returns {Object} Initialized ACE editor instance
   */
  initializeEditor(
    element,
    {
      mode = null,
      theme = 'ace/theme/twilight',
      tabSize = 2,
      wrapMode = true,
      highlightActiveLine = false,
      enableAutocompletion = true,
      enableLiveAutocompletion = true,
      completers = [],
      readOnly = false,
      hideCursor = false,
      value = '',
      vimModeSaveFn = null,
      onChange = null,
    } = {},
  ) {
    const editor = ace.edit(element)
    editor.setTheme(theme)

    if (mode) {
      editor.session.setMode(mode)
    }

    editor.session.setTabSize(tabSize)
    editor.session.setUseWrapMode(wrapMode)
    editor.$blockScrolling = Infinity

    if (enableAutocompletion) {
      editor.setOption('enableBasicAutocompletion', true)
    }

    if (enableLiveAutocompletion) {
      editor.setOption('enableLiveAutocompletion', true)
    }

    if (completers.length > 0) {
      editor.completers = completers
    }

    editor.setHighlightActiveLine(highlightActiveLine)

    if (value) {
      editor.setValue(value)
      editor.clearSelection()
    }

    if (readOnly) {
      editor.setReadOnly(true)
      if (hideCursor) {
        editor.renderer.$cursorLayer.element.style.display = 'none'
      }
    }

    this.applyVimModeIfEnabled(editor, { saveFn: vimModeSaveFn })

    if (onChange) {
      editor.session.on('change', onChange)
    }

    editor.focus()

    return editor
  },
}
