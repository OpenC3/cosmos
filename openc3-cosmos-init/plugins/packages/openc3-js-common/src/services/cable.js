/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
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
          let final_url =
            this._url +
            '?scope=' +
            encodeURIComponent(scope) +
            '&authorization=' +
            encodeURIComponent(localStorage.openc3Token)
          final_url = new URL(final_url, document.baseURI).href
          this._cable = createConsumer(final_url)
        }
        return this._cable.subscriptions.create(
          {
            channel,
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
