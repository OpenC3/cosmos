<!--
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
-->

<template>
  <g>
    <image
      v-for="image in images"
      :key="image.value"
      v-show="image.value == selectedValue"
      :href="image.url"
      :x="image.x"
      :y="image.y"
      :width="image.width"
      :height="image.height"
      @click="clickHandler"
    />
    <image
      v-if="defaultImage"
      v-show="showDefault"
      :href="defaultImage.url"
      :x="defaultImage.x"
      :y="defaultImage.y"
      :width="defaultImage.width"
      :height="defaultImage.height"
      @click="clickHandler"
    />
  </g>
</template>

<script>
import Widget from './Widget'
import ImageLoader from './ImageLoader'

export default {
  mixins: [Widget, ImageLoader],
  data: function () {
    return {
      images: [],
      defaultImage: null,
      screenTarget: null,
      screenName: null,
    }
  },
  computed: {
    selectedValue: function () {
      if (this.screenValues[this.valueId]) {
        return this.screenValues[this.valueId][0]
      }
      return null
    },
    showDefault: function () {
      return !this.images.some((image) => image.value == this.selectedValue)
    },
  },
  created: function () {
    // Look through the settings and get a reference to the screen
    this.appliedSettings.forEach((setting) => {
      if (setting[0] === 'SCREEN') {
        this.screenTarget = setting[1]
        this.screenName = setting[2]
      }
    })

    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${
      this.parameters[2]
    }__${this.parameters[3] || 'RAW'}`
    this.$emit('addItem', this.valueId)

    // Set value images data
    const promises = this.appliedSettings
      .filter((setting) => setting[0] === 'IMAGE')
      .map(async (setting) => {
        let url = setting[2]
        if (!url.startsWith('http')) {
          url = await this.getPresignedUrl(url)
        }

        return {
          url,
          value: setting[1],
          x: setting[3],
          y: setting[4],
          width: setting[5],
          height: setting[6],
        }
      })
    Promise.all(promises).then((images) => {
      this.images = images
    })

    // Set default image data
    if (this.parameters[4]) {
      const defaultImage = {
        x: this.parameters[5],
        y: this.parameters[6],
        width: this.parameters[7] ? `${this.parameters[7]}px` : '100%',
        height: this.parameters[8] ? `${this.parameters[8]}px` : '100%',
      }

      let url = this.parameters[4]
      if (!url.startsWith('http')) {
        this.getPresignedUrl(url).then((response) => {
          this.defaultImage = {
            ...defaultImage,
            url: response,
          }
        })
      } else {
        this.defaultImage = {
          ...defaultImage,
          url,
        }
      }
    }
  },
  destroyed: function () {
    this.$emit('deleteItem', this.valueId)
  },
  methods: {
    clickHandler() {
      if (this.screenTarget && this.screenName) {
        this.$emit('open', this.screenTarget, this.screenName)
      }
    },
  },
}
</script>
