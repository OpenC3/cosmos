import axios from 'axios'
import { OpenC3Api } from '@openc3/js-common/services'

export default class PluginStoreApi {
  cosmosApi = null
  refreshingUrl = false
  storeUrl = 'https://store.openc3.com'

  constructor() {
    this.cosmosApi = new OpenC3Api()
    this.refreshPluginStoreUrl()
  }

  async getAll() {
    while (this.refreshingUrl) {
      await new Promise((res) => setTimeout(res, 30))
    }
    const pluginsJsonUrl = new URL('/cosmos_plugins/json', this.storeUrl)
    return await axios.get(pluginsJsonUrl)
  }

  getBySha() {
    // TODO
    return null
  }

  async refreshPluginStoreUrl() {
    this.refreshingUrl = true
    const response = await this.cosmosApi.get_setting('store_url')
    if (response) {
      this.storeUrl = response
    }
    this.refreshingUrl = false
  }
}
