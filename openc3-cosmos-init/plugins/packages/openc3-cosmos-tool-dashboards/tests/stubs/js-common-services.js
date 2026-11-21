/*
# Copyright 2026 OpenC3, Inc.
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

// @openc3/js-common/services for unit tests: the real config parser (no
// browser needed), the network services stubbed (they read location and
// open sockets)
export {
  ConfigParserError,
  ConfigParserService,
} from '../../../openc3-js-common/src/services/configParser'

export const Api = {
  get: () => Promise.resolve({ data: [] }),
  post: () => Promise.resolve({}),
}
export const axios = Api
export class Cable {
  createSubscription() {
    return Promise.resolve({ unsubscribe: () => Promise.resolve() })
  }
}
export class OpenC3Api {
  get_tlm_values() {
    return Promise.resolve([])
  }
}
