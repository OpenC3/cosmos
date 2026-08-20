/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
*/

const emptyPromise = function (resolution = null) {
  return new Promise((resolve) => {
    resolve(resolution)
  })
}
// Signals that there is no usable token and the browser is being redirected to
// the login page. Callers must abandon the request they were about to make:
// sending it can only 401, which does nothing but log a server side error.
// Identified by name rather than by class so code shared with enterprise (which
// has its own Auth implementation) doesn't have to import this file.
class AuthRequiredError extends Error {
  constructor(message = 'Authentication required') {
    super(message)
    this.name = 'AuthRequiredError'
  }
}

class Auth {
  // @param value [Number] unused in core, minimum token validity in seconds
  // @param from_401 [Boolean] whether a request just came back unauthorized
  // @return [Promise<Boolean>] whether the token was refreshed, or a rejection
  //   with an AuthRequiredError if we're redirecting to login instead
  updateToken(value, from_401 = false) {
    if (!localStorage.openc3Token || from_401) {
      this.clearTokens()
      this.login(location.href)
      return Promise.reject(new AuthRequiredError())
    }
    return emptyPromise()
  }
  setTokens() {}
  clearTokens() {
    delete localStorage.openc3Token
  }
  // Navigating to login is idempotent: a page load with no token calls
  // updateToken once per request, and each of those would otherwise schedule
  // its own redirect. Only the first one that actually navigates counts - the
  // flag is set inside the branch so an already-on-login call doesn't block a
  // later user initiated login.
  login(redirect) {
    if (this.redirectingToLogin) return
    let url = new URL(redirect)
    let result = url.pathname
    if (url.search) {
      result = result + url.search
    }
    // redirect to login if we're not already there
    if (!/^\/login/.test(location.pathname)) {
      this.redirectingToLogin = true
      location = `/login?redirect=${encodeURI(result)}`
    }
  }
  logout() {
    this.clearTokens()
    location.reload()
  }
  user() {
    return { name: 'Anonymous' }
  }
  userroles() {
    return ['admin']
  }
  getInitOptions() {}
  init() {
    return emptyPromise(true)
  }
}
let OpenC3Auth = new Auth()

Object.defineProperty(OpenC3Auth, 'defaultMinValidity', {
  value: 30,
  writable: false,
  enumerable: true,
  configurable: false,
})
