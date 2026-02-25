/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
*/

const emptyPromise = function (resolution = null) {
  return new Promise((resolve) => {
    resolve(resolution)
  })
}
class Auth {
  updateToken(value, from_401 = false) {
    if (!localStorage.openc3Token || from_401) {
      this.clearTokens()
      this.login(location.href)
    }
    return emptyPromise()
  }
  setTokens() {}
  clearTokens() {
    delete localStorage.openc3Token
  }
  login(redirect) {
    let url = new URL(redirect)
    let result = url.pathname
    if (url.search) {
      result = result + url.search
    }
    // redirect to login if we're not already there
    if (!/^\/login/.test(location.pathname))
      location = `/login?redirect=${encodeURI(result)}`
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
