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

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  data: function () {
    return {
      classification: {
        text: '',
        fontColor: 'white',
        backgroundColor: 'red',
        topHeight: 0,
        bottomHeight: 0,
      },
    }
  },
  computed: {
    classificationStyles: function () {
      // JavaScript can't access CSS psudo-elements (::before and ::after).
      // This string sets these JS values to CSS variables, accessible to
      // the style sheet via the style attribute on #app
      return [
        `--classification-text:"${this.classification.text}";`,
        `--classification-font-color:${this.classification.fontColor};`,
        `--classification-background-color:${this.classification.backgroundColor};`,
        `--classification-height-top:${this.classification.topHeight}px;`,
        `--classification-height-bottom:${this.classification.bottomHeight}px;`,
      ].join('')
    },
  },
  created: function () {
    const api = new OpenC3Api()
    api
      .get_setting('classification_banner')
      .then((response) => {
        if (response) {
          this.classification = JSON.parse(response)
        }
      })
      .catch((error) => {
        // Do nothing
      })
  },
}
</script>
