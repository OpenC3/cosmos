/*
# Copyright 2025, OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import axios from 'axios'
import { OpenC3Api } from '@openc3/js-common/services'

const SETTING_NAME = 'store_url'

export default class PluginStoreApi {
  cosmosApi = null
  refreshingUrl = false
  storeUrl = 'https://store.openc3.com'

  constructor() {
    this.cosmosApi = new OpenC3Api()
    this.refreshPluginStoreUrl()
  }

  async waitForRefresh() {
    while (this.refreshingUrl) {
      await new Promise((res) => setTimeout(res, 30))
    }
  }

  async getStoreUrl() {
    await this.waitForRefresh()
    return this.storeUrl
  }

  async getAll() {
    await this.waitForRefresh()
    const pluginsJsonUrl = new URL('/cosmos_plugins/json', this.storeUrl)
    return await axios.get(pluginsJsonUrl)
  }

  getBySha() {
    // TODO
    return null
  }

  async refreshPluginStoreUrl(newUrl = null) {
    this.refreshingUrl = true
    if (newUrl) {
      this.storeUrl = newUrl
      await this.cosmosApi.set_setting(SETTING_NAME, this.storeUrl)
    } else {
      const response = await this.cosmosApi.get_setting(SETTING_NAME)
      if (response) {
        this.storeUrl = response
      }
    }
    this.refreshingUrl = false
  }
}
