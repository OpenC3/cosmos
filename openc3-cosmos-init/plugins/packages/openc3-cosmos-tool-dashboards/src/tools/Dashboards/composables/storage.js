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

// Per browser preferences. localStorage throws when it's blocked (some
// private windows, strict privacy settings), so every access is guarded:
// reads fall back and writes just don't stick.

export function readString(key) {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

// null or undefined removes the key
export function writeString(key, value) {
  try {
    if (value == null) localStorage.removeItem(key)
    else localStorage.setItem(key, String(value))
  } catch {
    // Storage blocked: lasts until the page reloads
  }
}

export function readJson(key, fallback = null) {
  try {
    const text = localStorage.getItem(key)
    return text === null ? fallback : JSON.parse(text)
  } catch {
    return fallback
  }
}

export function writeJson(key, value) {
  writeString(key, JSON.stringify(value))
}
