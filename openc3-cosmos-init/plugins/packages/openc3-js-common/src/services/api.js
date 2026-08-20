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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import axios from './axios'
import { isAuthRequiredError, refreshToken } from './authGuard'

const request = async function (
  method,
  url,
  {
    data,
    params = {},
    headers,
    noAuth = false,
    optionalAuth = false,
    noScope = false,
    onUploadProgress = false,
    responseType,
  } = {},
) {
  if (!noAuth) {
    if (optionalAuth) {
      // Public bootstrap endpoints (e.g. tools/all, which AppNav needs to
      // render the login page itself) must still be sent with no token.
      // Refresh if we can and send whatever token we end up with, but never
      // let a missing one block the request.
      try {
        await refreshToken()
      } catch (error) {
        if (!isAuthRequiredError(error)) {
          throw error
        }
      }
      if (localStorage.openc3Token) {
        headers['Authorization'] = localStorage.openc3Token
      }
    } else {
      // Throws an AuthRequiredError if we have no token, in which case we're
      // being redirected to login and must not send the request
      await refreshToken()
      headers['Authorization'] = localStorage.openc3Token
    }
  }
  // Everything from the front-end is manual by default
  // The various api methods decide whether to pass the manual
  // flag to the authorize routine
  headers['manual'] = true
  if (!noScope && !params['scope']) {
    params['scope'] = window.openc3Scope
  }
  return axios({
    method,
    url,
    data,
    params,
    headers,
    onUploadProgress,
    responseType,
  })
}

const acceptOnlyDefaultHeaders = {
  Accept: 'application/json',
}

const fullDefaultHeaders = {
  ...acceptOnlyDefaultHeaders,
  'Content-Type': 'application/json',
}

export default {
  get: function (
    path,
    {
      params,
      headers = acceptOnlyDefaultHeaders,
      noScope,
      noAuth,
      optionalAuth,
      onUploadProgress,
      responseType,
    } = {},
  ) {
    return request('get', path, {
      params,
      headers,
      noScope,
      noAuth,
      optionalAuth,
      onUploadProgress,
      responseType,
    })
  },

  put: function (
    path,
    {
      data,
      params,
      headers = fullDefaultHeaders,
      noScope,
      noAuth,
      onUploadProgress,
    } = {},
  ) {
    return request('put', path, {
      data,
      params,
      headers,
      noScope,
      noAuth,
      onUploadProgress,
    })
  },

  post: function (
    path,
    {
      data,
      params,
      headers = fullDefaultHeaders,
      noScope,
      noAuth,
      onUploadProgress,
      responseType,
    } = {},
  ) {
    return request('post', path, {
      data,
      params,
      headers,
      noScope,
      noAuth,
      onUploadProgress,
      responseType,
    })
  },

  delete: function (
    path,
    {
      params,
      headers = acceptOnlyDefaultHeaders,
      noScope,
      noAuth,
      onUploadProgress,
    } = {},
  ) {
    return request('delete', path, {
      params,
      headers,
      noScope,
      noAuth,
      onUploadProgress,
    })
  },
}
