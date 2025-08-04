/*
# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { OpenC3Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      api: new OpenC3Api(),
      errorText: '',
      errorLoading: false,
      errorSaving: false,
      successSaving: false,
    }
  },
  methods: {
    loadSetting: function (setting, kwparams) {
      this.api
        .get_setting(setting, kwparams)
        .then((response) => {
          this.parseSetting(response)
        })
        .catch((error) => {
          this.parseSetting(null)
          this.errorText = error
          this.errorLoading = true
        })
    },
    saveSetting: function (setting, jsonString, kwparams) {
      this.api
        .set_setting(setting, jsonString, kwparams)
        .then(() => {
          this.errorSaving = false
          this.successSaving = true
        })
        .catch(() => {
          this.errorSaving = true
          this.successSaving = false
        })
    },
    parseSetting: function (response) {},
  },
}
