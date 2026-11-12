/*
# Copyright 2026 OpenC3, Inc.
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

// userAgentData reports 'macOS', navigator.platform reports 'MacIntel'
export const isMac = /mac|iphone|ipad/i.test(
  navigator.userAgentData?.platform || navigator.platform || '',
)

// macOS menus show modifiers as symbols in this order with no separator
const MAC_MODIFIERS = { Ctrl: '⌃', Alt: '⌥', Shift: '⇧', Mod: '⌘' }

/**
 * Format a shortcut like 'Mod+Shift+S' for the current platform:
 * '⇧⌘S' on macOS and 'Ctrl+Shift+S' elsewhere. Mod is Command on macOS
 * and Ctrl everywhere else.
 * @param {string} shortcut
 */
export function formatShortcut(shortcut) {
  const parts = shortcut.split('+')
  const key = parts.pop()
  if (isMac) {
    const symbols = Object.keys(MAC_MODIFIERS)
      .filter((modifier) => parts.includes(modifier))
      .map((modifier) => MAC_MODIFIERS[modifier])
    return symbols.join('') + key
  }
  return [...parts.map((part) => (part === 'Mod' ? 'Ctrl' : part)), key].join(
    '+',
  )
}
