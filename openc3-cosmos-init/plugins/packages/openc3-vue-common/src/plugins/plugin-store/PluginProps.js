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

import { OpenC3Api } from '@openc3/js-common/services'

const settingName = 'store_url'
export default {
  props: {
    id: Number,
    name: String,
    title: String,
    // titleSlug: String,
    author: String,
    // authorSlug: String,
    description: String,
    keywords: Array,
    img_path: String,
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
      _api: new OpenC3Api(),
      _storeUrl: '',
    }
  },
  computed: {
    plugin: function () {
      return {
        id: this.id,
        name: this.name,
        title: this.title,
        // titleSlug: this.titleSlug,
        author: this.author,
        // authorSlug: this.authorSlug,
        description: this.description,
        keywords: this.keywords,
        img_path: this.img_path,
        license: this.license,
        // rating: this.rating,
        // downloads: this.downloads,
        verified: this.verified,
        homepage: this.homepage,
        repository: this.repository,
        gem_url: this.gem_url,
        checksum: this.checksum,
      }
    },
    storeLink: function () {
      if (this.hasStoreListing) {
        return new URL(`/cosmos_plugins/${this.id}`, this._storeUrl)
      }
      return null
    },
    hasStoreListing: function () {
      return !!this.id
    },
    isPluginInstalled: function () {
      return !!this.name // Plugins only have a title, not a name, from the store
    },
  },
  created: function () {
    this._api
      .get_setting(settingName)
      .then((storeUrl) => (this._storeUrl = storeUrl || 'https://store.openc3.com'))
  },
}
