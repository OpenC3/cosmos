/*
# Copyright 2022 OpenC3, Inc.
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

import { sub, parse } from 'date-fns'
import Widget from './Widget'

export default {
  mixins: [Widget],
  data: function () {
    return {
      id: Math.floor(Math.random() * 100000000000), // Unique-ish
      state: 'start',
      items: [
        {
          targetName: this.parameters[0],
          packetName: this.parameters[1],
          itemName: this.parameters[2],
          valueType: this.parameters[3] || 'CONVERTED',
          reduced: this.parameters[4] || 'DECOM',
          reducedType: this.parameters[5] || null,
        },
      ],
      startTime: null,
      // 1hr of data by default
      secondsGraphed: 3600,
      pointsSaved: 3600,
      pointsGraphed: 3600,
      // Make it a decently sized graph
      size: {
        height: 300,
        width: 400,
      },
    }
  },
  created: function () {
    this.settings.forEach((setting) => {
      switch (setting[0]) {
        case 'ITEM':
          this.items.push({
            targetName: setting[1],
            packetName: setting[2],
            itemName: setting[3],
            valueType: setting[4] || 'CONVERTED',
            reduced: setting[5] || 'DECOM',
            reducedType: setting[6] || null,
          })
        case 'STARTTIME':
          let date = parse(setting[1], 'yyyy/MM/dd HH:mm:ss', new Date())
          this.startTime = date.getTime() * 1000000 // nanoseconds
          break
        case 'HISTORY':
          let amount = parseInt(setting[1].slice(0, setting[1].length - 1))
          let key = null
          let multiplier = 1
          switch (setting[1][setting[1].length - 1]) {
            case 'd':
              key = 'days'
              multiplier = 3600 * 24
              break
            case 'h':
              key = 'hours'
              multiplier = 3600
              break
            case 'm':
              key = 'minutes'
              multiplier = 60
              break
            case 's':
              key = 'seconds'
              break
            default:
              throw new Error(`Unknown time suffix: ${setting[1]}!`)
          }
          let obj = {}
          obj[key] = amount
          this.startTime = sub(new Date(), obj).getTime() * 1000000
          if (amount * multiplier > this.secondsGraphed) {
            this.secondsGraphed = amount * multiplier
          }
          if (amount * multiplier > this.pointsSaved) {
            this.pointsSaved = amount * multiplier
          }
          if (amount * multiplier > this.pointsGraphed) {
            this.pointsGraphed = amount * multiplier
          }
          break
        case 'SECONDSGRAPHED':
          this.secondsGraphed = parseInt(setting[1])
          break
        case 'POINTSSAVED':
          this.pointsSaved = parseInt(setting[1])
          break
        case 'POINTSGRAPHED':
          this.pointsGraphed = parseInt(setting[1])
          break
        case 'SIZE':
          this.size.width = parseInt(setting[1])
          this.size.height = parseInt(setting[2])
          break
      }
    })
    if (this.screen) {
      this.items.map((item) =>
        this.screen.addItem(
          `${item.targetName}__${item.packetName}__${item.itemName}__${item.valueType}`,
        ),
      )
    }
  },
  destroyed() {
    if (this.screen) {
      this.items.map((item) =>
        this.screen.deleteItem(
          `${item.targetName}__${item.packetName}__${item.itemName}__${item.valueType}`,
        ),
      )
    }
  },
}
