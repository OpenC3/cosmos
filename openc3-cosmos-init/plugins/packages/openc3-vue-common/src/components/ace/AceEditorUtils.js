/*
# Copyright 2024, OpenC3, Inc.
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

import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/keybinding-vim'
import 'ace-builds/src-min-noconflict/ext-searchbox'

const VIM_MODE_STORAGE_KEY = 'openc3-ace-vim-mode-enabled'

export default {
  /**
   * Check if vim mode is enabled from localStorage
   * @returns {boolean} true if vim mode is enabled
   */
  isVimModeEnabled() {
    return localStorage.getItem(VIM_MODE_STORAGE_KEY) === 'true'
  },

  /**
   * Toggle vim mode on/off and save to localStorage
   * @param {Object} editor - Ace editor instance
   * @returns {boolean} new vim mode state
   */
  toggleVimMode(editor) {
    const isEnabled = this.isVimModeEnabled()
    
    if (isEnabled) {
      // Disable vim mode
      editor.setKeyboardHandler(null)
      localStorage.setItem(VIM_MODE_STORAGE_KEY, 'false')
      return false
    } else {
      // Enable vim mode
      editor.setKeyboardHandler('ace/keyboard/vim')
      localStorage.setItem(VIM_MODE_STORAGE_KEY, 'true')
      return true
    }
  },

  /**
   * Apply vim mode to editor if enabled in localStorage
   * @param {Object} editor - Ace editor instance
   */
  applyVimModeIfEnabled(editor) {
    if (this.isVimModeEnabled()) {
      editor.setKeyboardHandler('ace/keyboard/vim')
    } else {
      editor.setKeyboardHandler(null)
    }
  },

  /**
   * Add vim mode toggle to editor context menu
   * @param {Object} editor - Ace editor instance
   */
  addVimModeToggleToContextMenu(editor) {
    // Get the existing editor context menu
    const contextMenu = document.getElementById(editor.container.id + '_contextmenu')
    const hasExistingMenu = !!contextMenu

    if (hasExistingMenu) {
      // Add to existing context menu
      this._addVimModeItemToExistingContextMenu(editor, contextMenu)
    } else {
      // Create new context menu
      this._createContextMenuWithVimModeToggle(editor)
    }
  },

  /**
   * Private method to add vim mode toggle to existing context menu
   * @param {Object} editor - Ace editor instance
   * @param {HTMLElement} contextMenu - Existing context menu element
   * @private
   */
  _addVimModeItemToExistingContextMenu(editor, contextMenu) {
    // Create separator and menu item
    const separator = document.createElement('div')
    separator.className = 'ace_line_group ace_separator'

    const menuItem = this._createVimModeMenuItem(editor)
    
    // Add to existing menu
    contextMenu.appendChild(separator)
    contextMenu.appendChild(menuItem)
  },

  /**
   * Private method to create a new context menu with vim mode toggle
   * @param {Object} editor - Ace editor instance
   * @private
   */
  _createContextMenuWithVimModeToggle(editor) {
    // Create a custom context menu
    editor.container.addEventListener('contextmenu', (event) => {
      event.preventDefault()
      
      // Create the menu container
      const contextMenu = document.createElement('div')
      contextMenu.id = editor.container.id + '_contextmenu'
      contextMenu.className = 'ace_contextmenu'
      contextMenu.style.position = 'absolute'
      contextMenu.style.zIndex = '1000'
      contextMenu.style.backgroundColor = '#333'
      contextMenu.style.border = '1px solid #555'
      contextMenu.style.color = '#eee'
      contextMenu.style.padding = '5px 0'
      contextMenu.style.boxShadow = '0 2px 10px rgba(0,0,0,0.5)'
      
      // Create the vim mode toggle menu item
      const menuItem = this._createVimModeMenuItem(editor)
      contextMenu.appendChild(menuItem)
      
      // Position the menu at click location
      contextMenu.style.left = event.clientX + 'px'
      contextMenu.style.top = event.clientY + 'px'
      
      // Add menu to document
      document.body.appendChild(contextMenu)
      
      // Close menu when clicking outside
      const closeMenu = () => {
        if (document.body.contains(contextMenu)) {
          document.body.removeChild(contextMenu)
        }
        document.removeEventListener('click', closeMenu)
      }
      
      setTimeout(() => {
        document.addEventListener('click', closeMenu)
      }, 0)
    })
  },

  /**
   * Private method to create the vim mode toggle menu item
   * @param {Object} editor - Ace editor instance
   * @returns {HTMLElement} menu item element
   * @private
   */
  _createVimModeMenuItem(editor) {
    const menuItem = document.createElement('div')
    menuItem.className = 'ace_line_group'
    menuItem.style.padding = '5px 10px'
    menuItem.style.cursor = 'pointer'
    menuItem.style.whiteSpace = 'nowrap'
    
    this._updateVimModeMenuItemText(menuItem)
    
    menuItem.onmouseover = () => {
      menuItem.style.backgroundColor = '#444'
    }
    
    menuItem.onmouseout = () => {
      menuItem.style.backgroundColor = 'transparent'
    }
    
    menuItem.onclick = () => {
      this.toggleVimMode(editor)
      this._updateVimModeMenuItemText(menuItem)
    }
    
    return menuItem
  },

  /**
   * Private method to update the vim mode menu item text
   * @param {HTMLElement} menuItem - Menu item element
   * @private
   */
  _updateVimModeMenuItemText(menuItem) {
    const isEnabled = this.isVimModeEnabled()
    menuItem.textContent = isEnabled ? 'Disable Vim Mode' : 'Enable Vim Mode'
  }
}