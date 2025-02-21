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
  const minEdgeVersion = 108 // December 2022
  const minSafariVersion = 16 // September 2022
  const currentMinVersionString = `c${minChromeVersion},f${minFirefoxVersion},e${minEdgeVersion},s${minSafariVersion}`

  const uaChrome = navigator.userAgent.match(/Chrome\/\d+/)
  const uaFirefox = navigator.userAgent.match(/Firefox\/\d+/)
  const uaEdge = navigator.userAgent.match(/Edg\/\d+/) // `/Edge\/\d+/` is Legacy Edge (pre-Chromium)
  const uaSafari = navigator.userAgent.match(/Safari\/\d+/)

  // Reset the nag counter when there are updates
  const isNewMinVersion =
    localStorage.lastCheckedBrowserVersions !== currentMinVersionString
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

  /* Order matters here for Edge, Chrome, and Safari because their user-agent strings match each other.
   * Edge: `Chrome/x Safari/x Edg/x`
   * Chrome: `Chrome/x Safari/x`
   * Safari: `Version/x Safari/x`
   * Firefox: `Firefox/x`
   *
   * If we need to get any fancier than this, we should look into a parser library
   * such as https://github.com/faisalman/ua-parser-js
   */
  if (uaEdge) {
    const version = parseUaVersion(uaEdge)
    if (version === NaN || version < minEdgeVersion) {
      localStorage.browserCheckAlertCounter++
      alert(
        `It looks like you're using an unsupported version of Edge. Please update to version ${minEdgeVersion} or later.`,
      )
    }
  } else if (uaChrome) {
    const version = parseUaVersion(uaChrome)
    if (version === NaN || version < minChromeVersion) {
      localStorage.browserCheckAlertCounter++
      alert(
        `It looks like you're using an unsupported version of Chrome. Please update to version ${minChromeVersion} or later.`,
      )
    }
  } else if (uaSafari) {
    const uaSafariVersion = navigator.userAgent.match(/Version\/\d+/)
    const version = parseUaVersion(uaSafariVersion)
    if (version === NaN || version < minSafariVersion) {
      localStorage.browserCheckAlertCounter++
      alert(
        `It looks like you're using an unsupported version of Safari. Please update to version ${minSafariVersion} or later.`,
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
