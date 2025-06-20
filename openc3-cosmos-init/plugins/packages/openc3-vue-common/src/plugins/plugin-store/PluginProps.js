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

import { PluginStoreApi } from '@/tools/admin/tabs/plugins'

export default {
  props: {
    id: Number,
    title: String,
    // titleSlug: String,
    author: String,
    // authorSlug: String,
    description: String,
    keywords: Array,
    image_url: String,
    license: String,
    // rating: Number,
    // downloads: Number,
    verified: Boolean,
    homepage: String,
    repository: String,
    gem_url: String,
    checksum: String,
  },
  data: function () {
    return {
      _storeApi: new PluginStoreApi(),
      _storeUrl: '',
    }
  },
  computed: {
    plugin: function () {
      return {
        id: this.id,
        title: this.title,
        // titleSlug: this.titleSlug,
        author: this.author,
        // authorSlug: this.authorSlug,
        description: this.description,
        keywords: this.keywords,
        image_url: this.image_url,
        license: this.license,
        // rating: this.rating,
        // downloads: this.downloads,
        verified: this.verified,
        homepage: this.homepage,
        repository: this.repository,
        gem_url: this.gem_url,
        checksum: this.gemSha,
      }
    },
    storeLink: function () {
      return new URL(`/cosmos_plugins/${this.id}`, this._storeUrl)
    },
  },
  created: function () {
    this._storeApi.getStoreUrl().then((storeUrl) => (this._storeUrl = storeUrl))
  },
}
