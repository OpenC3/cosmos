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

import { createConsumer } from '@anycable/web'

export default class Cable {
  constructor(url = '/openc3-api/cable') {
    this._cable = null
    this._url = url
  }
  disconnect() {
    if (this._cable) {
      this._cable.cable.disconnect()
      this._cable = null
    }
  }
  createSubscription(channel, scope, callbacks = {}, additionalOptions = {}) {
    return OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
      (refreshed) => {
        if (refreshed) {
          OpenC3Auth.setTokens()
        }
        if (this._cable == null) {
          // Token is passed per-subscription as `params[:token]` (see
          // ApplicationCable::Channel#authenticate_subscription!) so it stays
          // out of the WebSocket URL — and therefore out of browser history
          // and proxy logs.
          const finalUrl = new URL(this._url, document.baseURI)
          finalUrl.searchParams.set('scope', scope)
          this._cable = createConsumer(finalUrl.href)
        }
        return this._cable.subscriptions.create(
          {
            channel,
            token: localStorage.openc3Token,
            ...additionalOptions,
          },
          callbacks,
        )
      },
    )
  }
  recordPing() {
    // Noop with Anycable
  }
}
