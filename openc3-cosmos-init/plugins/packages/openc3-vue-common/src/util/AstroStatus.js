/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

const _levels = [
  // order of levels from highest to lowest
  'FATAL',
  'fatal',
  'ERROR',
  'critical',
  'serious',
  'WARN',
  'caution',
  'INFO',
  'normal',
  'standby',
  'off',
  'DEBUG',
]

const _getLevelIndeces = function (levels) {
  return levels.map((level) => _levels.indexOf(level))
}

const highestLevel = function (levels) {
  const indices = _getLevelIndeces(levels)
  const index = Math.min(...indices)
  return _levels[index]
}

const lowestLevel = function (levels) {
  const indices = _getLevelIndeces(levels)
  const index = Math.max(...indices)
  return _levels[index]
}

const orderByLevel = function (objects, levelGetter = (x) => x.level) {
  return objects.sort((a, b) => {
    return _levels.indexOf(levelGetter(a)) - _levels.indexOf(levelGetter(b))
  })
}

const groupByLevel = function (objects, levelGetter = (x) => x.level) {
  return objects.reduce((groups, obj) => {
    const level = levelGetter(obj)
    groups[level] ||= []
    groups[level].push(obj)
    return groups
  }, {})
}

export { highestLevel, lowestLevel, orderByLevel, groupByLevel }
