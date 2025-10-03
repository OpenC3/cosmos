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

import { Api, OpenC3Api } from '@openc3/js-common/services'

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
    licenses: Array,
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
      imageContents: null,
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
        licenses: this.licenses,
        // rating: this.rating,
        // downloads: this.downloads,
        verified: this.verified,
        homepage: this.homepage,
        repository: this.repository,
        gem_url: this.gem_url,
        checksum: this.checksum,
      }
    },
    imageContentsWithMimeType: function () {
      if (this.imageContents) {
        const magicNumbers = {
          'image/bmp': [0x42, 0x4d],
          'image/jpeg': [0xff, 0xd8, 0xff],
          'image/png': [0x89, 0x50, 0x4e, 0x47],
          'image/gif': [0x47, 0x49, 0x46, 0x38],
          'image/webp': [0x52, 0x49, 0x46, 0x46],
        }
        const fileHead = new TextEncoder()
          .encode(window.atob(this.imageContents.slice(0, 6))) // only atob as much as we need
          .slice(1) // second call to slice on the decoded data because base64 bytes aren't 1:1
        const found = Object.entries(magicNumbers).find(([_, magicNumber]) => {
          return magicNumber.every((byte, i) => byte === fileHead[i])
        })
        if (found) {
          const [mimeType] = found
          return `data:${mimeType};base64,${this.imageContents}`
        }
      }
      return undefined
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
    hasDetails: function () {
      if (this.hasStoreListing) {
        return true
      }
      return !!this.title && !!this.description
    },
    isPluginInstalled: function () {
      return !!this.name // Plugins only have a title, not a name, from the store
    },
  },
  created: async function () {
    const defaultStoreUrl = 'https://store.openc3.com'
    try {
      this._storeUrl =
        (await this._api.get_setting(settingName)) || defaultStoreUrl
    } catch (e) {
      this._storeUrl = defaultStoreUrl
    }
    if (this.img_path) {
      try {
        const params = new URLSearchParams({
          volume: 'OPENC3_GEMS_VOLUME',
          scope: window.openc3Scope,
        })
        const { data } = await Api.get(
          `/openc3-api/storage/download_file/${encodeURIComponent(this.img_path)}?${params}`,
        )
        this.imageContents = data.contents
      } catch (e) {
        // Failed to get image, don't do anything
      }
    }
  },
}
