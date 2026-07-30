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

// How long to wait before rebuilding a consumer whose subscribe failed
// unrecoverably. Long enough to not spin when the backend is unreachable, short
// enough that a tool isn't visibly stuck.
const RECOVERY_DELAY = 1000

// Wraps an anycable subscription so one that dies unrecoverably is replaced
// transparently, keeping the object the caller holds valid across the swap.
//
// The anycable client only retries a subscribe itself when its own send fails
// with a DisconnectedError. When the WebSocket has closed but the client hasn't
// processed the close yet (e.g. the tab was starved of CPU long enough for the
// server to drop the connection), the transport instead throws a plain
// `Error('WebSocket is not connected')` from inside the protocol's subscribe
// promise -- after it recorded the subscription as pending but before it armed
// the timers that would expire it. The client logs "failed to subscribe", closes
// the subscription, and leaves the pending entry behind forever, so every later
// subscribe for that channel on that consumer is rejected with "Already
// subscribing". Callers were left waiting on events that would never arrive --
// Script Runner connecting to a running script, for instance, sat on
// "Connecting..." indefinitely. Only a new consumer clears that state, so
// recovery is handled by Cable rather than per subscription.
class ResilientSubscription {
  constructor(cable, channel, scope, callbacks, additionalOptions) {
    this._cable = cable
    this._channel = channel
    this._scope = scope
    this._callbacks = callbacks
    this._additionalOptions = additionalOptions
    this._subscription = null
    this._unsubscribed = false
  }

  get identifier() {
    return this._subscription?.identifier
  }

  perform(action, data) {
    return this._subscription?.perform(action, data)
  }

  send(data) {
    return this._subscription?.send(data)
  }

  unsubscribe() {
    this._unsubscribed = true
    this._cable._forget(this)
    return this._subscription?.unsubscribe()
  }

  _subscribe(consumer) {
    // The token refresh in Cable._resubscribe is async, so the caller can
    // unsubscribe before we ever get here.
    if (this._unsubscribed) {
      return
    }
    this._subscription = consumer.subscriptions.create(
      {
        channel: this._channel,
        token: localStorage.openc3Token,
        ...this._additionalOptions,
      },
      {
        ...this._callbacks,
        disconnected: (data) => {
          // allowReconnect false means the client has given up on this
          // subscription: either we unsubscribed it (nothing to do) or the
          // subscribe failed unrecoverably and the consumer needs rebuilding.
          if (!this._unsubscribed && data?.allowReconnect === false) {
            this._cable._scheduleRecovery()
          }
          this._callbacks.disconnected?.(data)
        },
      },
    )
  }
}

export default class Cable {
  constructor(url = '/openc3-api/cable') {
    this._cable = null
    this._url = url
    this._subscriptions = new Set()
    this._recovery = null
  }
  disconnect() {
    this._cancelRecovery()
    this._subscriptions.clear()
    if (this._cable) {
      this._cable.cable.disconnect()
      this._cable = null
    }
  }
  createSubscription(channel, scope, callbacks = {}, additionalOptions = {}) {
    const subscription = new ResilientSubscription(
      this,
      channel,
      scope,
      callbacks,
      additionalOptions,
    )
    this._subscriptions.add(subscription)
    return this._resubscribe(subscription).then(() => subscription)
  }
  // Subscribe (or re-subscribe) on this cable's consumer, refreshing the auth
  // token first since the token is passed as a subscription param and a retry
  // can happen much later than the original subscribe.
  _resubscribe(subscription) {
    // Create the consumer up front (createConsumer is lazy -- no socket is
    // opened until the first subscribe) so concurrent calls can't each see a
    // null _cable and build a consumer of their own.
    if (this._cable == null) {
      // Token is passed per-subscription as `params[:token]` (see
      // ApplicationCable::Channel#authenticate_subscription!) so it stays out
      // of the WebSocket URL — and therefore out of browser history and proxy
      // logs.
      const finalUrl = new URL(this._url, document.baseURI)
      finalUrl.searchParams.set('scope', subscription._scope)
      this._cable = createConsumer(finalUrl.href)
    }
    return OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
      (refreshed) => {
        if (refreshed) {
          OpenC3Auth.setTokens()
        }
        if (this._cable) {
          subscription._subscribe(this._cable)
        }
      },
    )
  }
  // Replace the consumer and re-subscribe everything on it. Dropping the old
  // consumer is what clears the leaked pending subscription (see
  // ResilientSubscription), and reconnecting from scratch rather than resuming
  // the session makes the server re-run each channel's subscribed callback.
  _scheduleRecovery() {
    if (this._recovery) {
      return
    }
    this._recovery = setTimeout(() => {
      this._recovery = null
      const subscriptions = [...this._subscriptions]
      if (this._cable) {
        this._cable.cable.disconnect()
        this._cable = null
      }
      // Sequentially so the first one creates the consumer the rest reuse
      subscriptions
        .reduce(
          (chain, subscription) =>
            chain.then(() => this._resubscribe(subscription)),
          Promise.resolve(),
        )
        .catch((error) => console.error('failed to recover cable', error))
    }, RECOVERY_DELAY)
  }
  _cancelRecovery() {
    if (this._recovery) {
      clearTimeout(this._recovery)
      this._recovery = null
    }
  }
  _forget(subscription) {
    this._subscriptions.delete(subscription)
    if (this._subscriptions.size === 0) {
      this._cancelRecovery()
    }
  }
  recordPing() {
    // Noop with Anycable
  }
}
