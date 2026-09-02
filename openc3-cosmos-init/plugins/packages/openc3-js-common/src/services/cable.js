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
// Works around an upstream bug in @anycable/core (through 1.1.6). When the
// WebSocket has closed but the client hasn't processed the close yet (e.g. the
// tab was starved of CPU long enough for the server to drop the connection),
// WebSocketTransport#send throws a plain `Error('WebSocket is not connected')`
// rather than the DisconnectedError that Cable#subscribe recognizes as "retry
// on reconnect". It therefore takes the fatal branch instead: it logs "failed
// to subscribe", closes the subscription and calls hub.unsubscribe, so the
// channel is gone for good and is never re-subscribed when the connection comes
// back. Callers were left waiting on events that would never arrive -- Script
// Runner connecting to a running script, for instance, sat on "Connecting..."
// indefinitely.
//
// Re-subscribing immediately isn't enough: ActionCableProtocol#subscribe
// recorded the subscription as pending before that send and never removes it
// (the ack timers are armed after the send, so nothing expires it). Until the
// consumer processes the socket close and resets the protocol, a re-subscribe
// for the same identifier is rejected with "Already subscribing" -- which is
// itself a plain Error, so it kills the channel the same way. Rebuilding the
// consumer clears that state deterministically, hence recovery lives on Cable
// rather than on the individual subscription.
//
// Upstream fix submitted; this can go once the released client carries it.
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
          // We tore this subscription down ourselves (unsubscribe, or the
          // whole cable disconnecting because the component unmounted). The
          // caller isn't interested and may already be half destroyed, so
          // don't report it as a connection problem.
          if (this._unsubscribed) {
            return
          }
          // allowReconnect false means the client has given up on this
          // subscription: the subscribe failed unrecoverably and the consumer
          // needs rebuilding.
          if (data?.allowReconnect === false) {
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
    // Mark the subscriptions dead before dropping them. Closing the consumer
    // rejects any subscribe still waiting on its ack, which surfaces as
    // disconnected with allowReconnect false -- that must not schedule a
    // recovery, since we just cancelled one and the consumer is going away.
    this._subscriptions.forEach((subscription) => {
      subscription._unsubscribed = true
    })
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
        .finally(() => {
          // clear recovery at the end of the callback to avoid overlapping recoveries
          this._recovery = null
        })
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
