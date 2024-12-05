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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { vuetify } from '@/plugins'
import ConfirmDialog from './ConfirmDialog.vue'

class Dialog {
  constructor() {
    this.mounted = false
    this.$root = null
  }

  mount() {
    if (this.mounted) return

    const app = window.Vue.createApp(ConfirmDialog)
    app.use(vuetify)

    const el = document.createElement('div')
    document.querySelector('#openc3-app-toolbar > div').appendChild(el)
    this.$root = app.mount(el)

    this.mounted = true
  }

  open({ title, text, okText, okClass, validateText, cancelText, html }) {
    // Per https://v2.vuetifyjs.com/en/features/theme/#customizing
    // okClass can be one of primary, secondary, accent, error, info, success, warning
    this.mount()
    return new Promise((resolve, reject) => {
      this.$root.dialog(
        { title, text, okText, okClass, validateText, cancelText, html },
        resolve,
        reject,
      )
    })
  }

  confirm(text, { okText = 'Ok', cancelText = 'Cancel', okClass = 'primary' }) {
    return this.open({
      title: 'Confirm',
      text: text,
      okText: okText,
      okClass: okClass,
      validateText: null,
      cancelText: cancelText,
      html: false,
    })
  }
  alert(text, { okText = 'Ok', html = false, okClass = 'primary' }) {
    return this.open({
      title: 'Alert',
      text: text,
      okText: okText,
      okClass: okClass,
      validateText: null,
      cancelText: null,
      html: html,
    })
  }
  validate(
    text,
    {
      okText = 'Ok',
      validateText = 'CONFIRM',
      cancelText = 'Cancel',
      okClass = 'primary',
    },
  ) {
    return this.open({
      title: 'Confirm',
      text: text,
      okText: okText,
      okClass: okClass,
      validateText: validateText,
      cancelText: cancelText,
      html: false,
    })
  }
}

export default {
  install(app, _) {
    const dialog = new Dialog()
    app.provide('dialog', dialog)
    if (!app.config.globalProperties.hasOwnProperty('$dialog')) {
      app.config.globalProperties.$dialog = dialog
    }
  },
}
