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

import { Marked } from 'marked'
import DOMPurify from 'dompurify'

// GitHub flavored markdown (tables, task lists, strikethrough), with single
// line breaks kept as written since panel notes are usually short lines
const marked = new Marked({ gfm: true, breaks: true, async: false })

// Links leave the dashboard in a new tab. Hooks are global to DOMPurify, so
// this one only touches what renderMarkdown sanitizes (marked with a flag).
let rendering = false
// (DOMPurify needs a DOM: without one, e.g. in unit tests, it has no hooks)
DOMPurify.addHook?.('afterSanitizeAttributes', (node) => {
  if (rendering && node.tagName === 'A' && node.getAttribute('href')) {
    node.setAttribute('target', '_blank')
    node.setAttribute('rel', 'noopener noreferrer')
  }
})

// Markdown to safe HTML: scripts, event handlers, styles and javascript:
// links are removed, since dashboards are shared files anyone with edit
// access can write
export function renderMarkdown(text) {
  const html = marked.parse(String(text ?? ''))
  rendering = true
  try {
    return DOMPurify.sanitize(html, {
      // Task lists keep their (disabled) checkboxes
      FORBID_TAGS: ['style', 'form', 'button', 'textarea', 'select'],
      FORBID_ATTR: ['style'],
    })
  } finally {
    rendering = false
  }
}
