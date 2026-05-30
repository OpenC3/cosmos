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
  // Lazily create the underlying anycable consumer. The token is passed
  // per-subscription as `params[:token]` (see
  // ApplicationCable::Channel#authenticate_subscription!) so it stays out of
  // the WebSocket URL — and therefore out of browser history and proxy logs.
  _ensureConsumer(scope) {
    if (this._cable == null) {
      const finalUrl = new URL(this._url, document.baseURI)
      finalUrl.searchParams.set('scope', scope)
      this._cable = createConsumer(finalUrl.href)
    }
    return this._cable
  }
  // Eagerly open the WebSocket connection ahead of any subscription. Channels
  // are Redis pub/sub with no history, so a subscription established after a
  // fast-starting backend resource has already published will miss those
  // events permanently. Warming the (cold) connection at mount removes the
  // handshake from the critical path so the later subscription is fast enough
  // to win the race. Connection-level auth is not required (auth is
  // per-subscription), so no token is needed here. Safe to call repeatedly.
  connect(scope) {
    return this._ensureConsumer(scope).cable.connect()
  }
  createSubscription(channel, scope, callbacks = {}, additionalOptions = {}) {
    return OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
      (refreshed) => {
        if (refreshed) {
          OpenC3Auth.setTokens()
        }
        return this._ensureConsumer(scope).subscriptions.create(
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
