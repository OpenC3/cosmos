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

// Whether an error means "there is no usable token, we're going to the login
// page". OpenC3Auth.updateToken rejects with one of these instead of resolving
// as if the token were good (see tool-base public/js/auth.js). Matched by name
// so this works with any Auth implementation, core or enterprise.
export function isAuthRequiredError(error) {
  return error?.name === 'AuthRequiredError'
}

// Whether an error is a request that came back unauthorized. A stale token
// rejects with the underlying axios error rather than an AuthRequiredError,
// since the token only turns out to be bad once the server says so.
// Api (axios) rejections carry the response, so the status is right there.
// OpenC3Api.exec rejects with a synthetic Error instead, which has no response
// at all - only a name copied from the JSON-RPC error class - so match on that
// too or every 401 through OpenC3Api slips past this check. The class comes
// from Ruby's Exception#as_json, which uses the fully namespaced name.
const UNAUTHORIZED_ERROR_CLASSES = new Set([
  'OpenC3::AuthError',
  'OpenC3::ForbiddenError',
])

export function isUnauthorizedError(error) {
  return (
    error?.response?.status === 401 ||
    error?.status === 401 ||
    UNAUTHORIZED_ERROR_CLASSES.has(error?.name)
  )
}

// Drop-in replacement for `.catch(console.error)` on requests that fire while
// the page is still deciding whether it's logged in. Neither a missing token nor
// a rejected one is an error worth a stack trace - the axios interceptor is
// already sending us to login - but everything else is.
export function logUnlessAuthRequired(error) {
  if (!isAuthRequiredError(error) && !isUnauthorizedError(error)) {
    console.error(error)
  }
}

export class AuthRequiredError extends Error {
  constructor(message = 'Authentication required') {
    super(message)
    this.name = 'AuthRequiredError'
  }
}

// Being sent to the login page isn't a bug, it's a navigation. Callers that
// don't catch it shouldn't fill the console with stack traces on the way out.
// Lives here rather than in tool-base so both core and enterprise get it, since
// each edition ships its own tool-base and its own Auth implementation.
if (!globalThis.__openc3AuthRejectionHandler) {
  globalThis.__openc3AuthRejectionHandler = true
  globalThis.addEventListener?.('unhandledrejection', (event) => {
    if (isAuthRequiredError(event.reason)) {
      event.preventDefault()
    }
  })
}

// Send the browser to login, at most once per page load. Redirecting is a
// navigation, so a second call can only mean the first one didn't take us
// anywhere - an Auth implementation that comes back still holding no usable
// token would otherwise bounce us through login forever. Keep rejecting so
// callers still abandon their requests; just stop asking to navigate.
let redirectingToLogin = false
function redirectToLogin() {
  if (redirectingToLogin) return
  redirectingToLogin = true
  OpenC3Auth.login()
}

// Refresh the auth token before making a request. Rejects with an
// AuthRequiredError - without making the request - when we have no token to
// send. Every such request is a guaranteed 401, and before this guard existed a
// single page load with a stale token produced a burst of them: each component
// fetching its own settings, all logged server side as errors.
export async function refreshToken() {
  try {
    const refreshed = await OpenC3Auth.updateToken(
      OpenC3Auth.defaultMinValidity,
    )
    if (refreshed) {
      OpenC3Auth.setTokens()
    }
  } catch (error) {
    if (isAuthRequiredError(error)) {
      throw error
    }
    // Any other failure to refresh means we can't authenticate either
    redirectToLogin()
    throw new AuthRequiredError(error?.message)
  }
  // An Auth implementation may redirect to login without rejecting, so don't
  // rely solely on the rejection above
  if (!localStorage.openc3Token) {
    redirectToLogin()
    throw new AuthRequiredError()
  }
}
