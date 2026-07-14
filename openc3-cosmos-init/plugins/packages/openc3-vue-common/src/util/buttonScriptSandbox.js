/*
# Copyright 2026, OpenC3, Inc.
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

// Runs a screen BUTTON widget's author-supplied JavaScript inside a sandboxed,
// opaque-origin <iframe> (see /sandbox.html) instead of eval()ing it in the main
// window. The sandbox cannot read localStorage (the session token), cookies, or
// the parent DOM, and its own CSP blocks all network access. Privileged
// operations (api.*, screen.open/close/closeAll, runScript, alert, and named
// widget value writes) are proxied back here over postMessage, where they run
// with the real, token-bearing objects. This is the fix for the stored,
// cross-user XSS in screen BUTTON widgets (the token can no longer be reached or
// exfiltrated by author JavaScript).

const SANDBOX_URL = '/sandbox.html'
// Idle (inactivity) watchdog: the sandbox is torn down if it goes this long
// without any bridge activity. It is generous (> the 60s OpenC3Api request
// timeout) because it measures inactivity, not total runtime, and it is paused
// while a hazardous-command confirmation dialog is awaiting the operator.
const DEFAULT_TIMEOUT = 120000
// Property/method names that must never be dispatched (prototype-pollution / escape guards)
const FORBIDDEN_KEYS = new Set(['constructor', '__proto__', 'prototype'])
// The only screen methods reachable from the sandbox
const SCREEN_METHODS = new Set(['open', 'close', 'closeAll'])
// Hazardous command retry mapping (parent-side, argument-based - no string munging)
const HAZARDOUS_RETRY = {
  cmd: 'cmd_no_hazardous_check',
  cmd_raw: 'cmd_raw_no_hazardous_check',
}

// Ensure a value survives structured clone across postMessage. Anything that
// isn't cloneable (functions, DOM nodes, class instances with methods) is
// dropped to undefined rather than throwing an opaque DataCloneError.
function toCloneable(value) {
  try {
    structuredClone(value)
    return value
  } catch {
    return undefined
  }
}

// Run one BUTTON script string in the sandbox. Returns a Promise that resolves
// when the whole script (all ';;' separated segments) has finished.
//
// options:
//   code                 - the raw BUTTON action string (parameters[1])
//   api                  - OpenC3Api instance (token-bearing, stays in parent)
//   screen               - the widget's screen object (open/close/closeAll)
//   runScript            - the widget's runScript(name, openScript, env) fn
//   setNamedWidgetValue  - fn(name, value) to write a named widget's value
//   snapshot             - { NAME: { text?, selected?, checked?, date?, time? } }
//   screenValues         - current telemetry values object
//   screenTimeZone       - 'local' | 'UTC'
//   onHazardous          - async fn(error) -> truthy to Send, falsy to Cancel
//   onCritical           - fn(error) shows the critical command dialog
//   timeout              - inactivity watchdog in ms (default 120000)
//   signal               - optional AbortSignal to tear down an in-flight run
export function runButtonScript(options) {
  const {
    code,
    api,
    screen,
    runScript,
    setNamedWidgetValue,
    snapshot = {},
    screenValues = {},
    screenTimeZone = 'local',
    onHazardous,
    onCritical,
    timeout = DEFAULT_TIMEOUT,
    signal,
  } = options

  return new Promise((resolve, reject) => {
    const onAbort = () => {
      finish(reject, new DOMException('Button script aborted', 'AbortError'))
    }
    const iframe = document.createElement('iframe')
    // No 'allow-same-origin' - the frame gets a unique opaque origin so it cannot
    // reach localStorage, cookies, or the parent DOM.
    iframe.setAttribute('sandbox', 'allow-scripts')
    iframe.setAttribute('aria-hidden', 'true')
    iframe.style.display = 'none'
    iframe.src = SANDBOX_URL

    let settled = false
    let watchdog = null

    const clearWatchdog = () => {
      if (watchdog) {
        clearTimeout(watchdog)
        watchdog = null
      }
    }
    // (Re)start the inactivity watchdog. Called on every message from the
    // sandbox so an actively-working script stays alive; a hung script (no
    // activity for `timeout` ms) is torn down.
    const armWatchdog = () => {
      clearWatchdog()
      watchdog = setTimeout(() => {
        finish(reject, new Error('Button script timed out'))
      }, timeout)
    }

    const teardown = () => {
      window.removeEventListener('message', onMessage)
      signal?.removeEventListener('abort', onAbort)
      clearWatchdog()
      iframe.remove()
    }

    const finish = (fn, value) => {
      if (settled) return
      settled = true
      teardown()
      fn(value)
    }

    const post = (message) => {
      // The frame is opaque-origin so targetOrigin must be '*'. This is safe:
      // only telemetry/command data flows inward - the session token is never
      // passed into the sandbox.
      iframe.contentWindow?.postMessage(message, '*')
    }

    // Call an api method, handling the hazardous / critical command flows
    // entirely here in the parent so the rich CriticalCmdError object never has
    // to cross the (lossy) structured-clone bridge.
    const callApi = async (method, args) => {
      try {
        return await api[method](...args)
      } catch (error) {
        const message = error?.message || ''
        if (message.includes('CriticalCmdError')) {
          onCritical?.(error)
          throw error // reject the segment; the sandbox logs and continues
        }
        if (message.includes('is Hazardous') && HAZARDOUS_RETRY[method]) {
          // The confirmation dialog is operator-paced; don't let the inactivity
          // watchdog fire while we wait for a human.
          clearWatchdog()
          const send = await onHazardous?.(error)
          armWatchdog()
          if (send) {
            return await api[HAZARDOUS_RETRY[method]](...args)
          }
          return undefined // Cancelled - command not sent, script continues
        }
        throw error
      }
    }

    const dispatch = async (message) => {
      const { id, target, method, name, op, args = [], value } = message
      try {
        let result
        switch (target) {
          case 'api':
            if (
              typeof method !== 'string' ||
              FORBIDDEN_KEYS.has(method) ||
              typeof api[method] !== 'function'
            ) {
              throw new Error(`Unknown api method: ${method}`)
            }
            result = await callApi(method, args)
            break
          case 'screen':
            if (!SCREEN_METHODS.has(method)) {
              throw new Error(`Unknown screen method: ${method}`)
            }
            result = screen[method](...args)
            if (result instanceof Promise) result = await result
            break
          case 'runScript':
            result = runScript(...args)
            if (result instanceof Promise) result = await result
            break
          case 'alert':
            result = window.alert(...args)
            break
          case 'namedWidget':
            if (
              op === 'setValue' &&
              typeof name === 'string' &&
              !FORBIDDEN_KEYS.has(name)
            ) {
              setNamedWidgetValue(name, value)
            } else {
              throw new Error(`Unknown namedWidget op: ${op}`)
            }
            break
          default:
            throw new Error(`Unknown bridge target: ${target}`)
        }
        post({ type: 'result', id, ok: true, value: toCloneable(result) })
      } catch (error) {
        post({
          type: 'result',
          id,
          ok: false,
          error: { name: error?.name, message: error?.message },
        })
      }
    }

    const onMessage = (event) => {
      // Authoritative source check. Opaque-origin frames all report
      // event.origin === 'null', so reference equality is the only reliable way
      // to know a message came from our frame.
      if (event.source !== iframe.contentWindow) return
      const message = event.data
      if (!message || typeof message !== 'object') return
      armWatchdog() // any activity from the sandbox resets the inactivity timer
      switch (message.type) {
        case 'ready':
          post({
            type: 'init',
            code,
            // Guard against reactive proxies / non-cloneable values so the
            // init postMessage never throws a DataCloneError.
            snapshot: toCloneable(snapshot) ?? {},
            screenValues: toCloneable(screenValues) ?? {},
            screenTimeZone,
          })
          break
        case 'call':
          dispatch(message)
          break
        case 'done':
          finish(resolve, undefined)
          break
      }
    }

    if (signal) {
      if (signal.aborted) {
        onAbort()
        return
      }
      signal.addEventListener('abort', onAbort, { once: true })
    }

    window.addEventListener('message', onMessage)
    armWatchdog()

    document.body.appendChild(iframe)
  })
}

export default runButtonScript
