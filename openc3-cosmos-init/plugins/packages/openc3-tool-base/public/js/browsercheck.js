/*
# Copyright 2024, OpenC3, Inc.
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

;(function () {
  const nagCount = 3

  const minChromeVersion = 108 // November 2022
  const minFirefoxVersion = 108 // December 2022
  const currentMinVersionString = `c${minChromeVersion},f${minFirefoxVersion}`

  const uaChrome = navigator.userAgent.match(/Chrome\/\d+/)
  const uaFirefox = navigator.userAgent.match(/Firefox\/\d+/)

  // Reset the nag counter when there are updates
  const isNewMinVersion = localStorage.lastCheckedBrowserVersions !== currentMinVersionString
  const isNewUaString = localStorage.lastUaString !== navigator.userAgent
  const isCounterUnset = parseInt(localStorage.browserCheckAlertCounter) === NaN
  if (isNewMinVersion || isNewUaString || isCounterUnset) {
    localStorage.lastCheckedBrowserVersions = currentMinVersionString
    localStorage.lastUaString = navigator.userAgent
    localStorage.browserCheckAlertCounter = 0
  }

  // Alert the user on page load a few times to get their attention,
  // but then be quiet in case they need to use an unsupported browser
  if (localStorage.browserCheckAlertCounter >= nagCount) {
    return
  }

  function parseUaVersion(ua) {
    return parseInt(ua.at(0).split('/').at(1))
  }

  if (uaChrome) {
    const version = parseUaVersion(uaChrome)
    if (version === NaN || version < minChromeVersion) {
      localStorage.browserCheckAlertCounter++
      alert(
        `It looks like you're using an unsupported version of Chrome. Please update to version ${minChromeVersion} or later.`,
      )
    }
  } else if (uaFirefox) {
    const version = parseUaVersion(uaFirefox)
    if (version === NaN || version < minFirefoxVersion) {
      localStorage.browserCheckAlertCounter++
      alert(
        `It looks like you're using an unsupported version of Firefox. Please update to version ${minFirefoxVersion} or later.`,
      )
    }
  } else {
    localStorage.browserCheckAlertCounter++
    alert(
      `It looks like you're using an unsupported browser. COSMOS might not work correctly. Please use Chrome (version ${minChromeVersion} or later) or Firefox (version ${minFirefoxVersion} or later).`,
    )
  }
})()
