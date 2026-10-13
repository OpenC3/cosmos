/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import search from 'approx-string-match'

// Tokenized search for dropdowns. Vuetify's built-in filter only matches a
// single contiguous substring, so finding HEALTH_STATUS means typing it
// exactly. Splitting the query on whitespace and requiring every token to
// appear somewhere in the value lets "heal stat" (or "stat heal") find
// HEALTH_STATUS. A token that doesn't appear exactly is retried allowing a
// small number of typos, so "hael sat" finds it too. The query is only split
// on whitespace, not on _ or /, so typing a full name still behaves the way
// it always has.

// How many typos to tolerate in a token. Short tokens are left alone because
// at two characters nearly everything is one edit away from everything else.
const maxEdits = function (length) {
  if (length <= 2) return 0
  if (length <= 5) return 1
  return 2
}

// Myers' algorithm counts insertions, deletions and substitutions, but it
// charges two edits for a transposition and "hael" has to reach "heal" on a
// one edit budget. Trying the token with each adjacent pair swapped covers
// that, since one swap undoes one transposition.
const swapVariants = function (token) {
  const variants = []
  for (let i = 0; i < token.length - 1; i++) {
    variants.push(
      token.slice(0, i) + token[i + 1] + token[i] + token.slice(i + 2),
    )
  }
  return variants
}

// Approximate substring search: the fewest edits (insert, delete, substitute
// or transpose adjacent characters) needed to turn some substring of text
// into token, along with where that substring is. Returns null if it can't be
// done within limit edits.
const fuzzyIndexOf = function (text, token, limit) {
  let best = null
  for (const match of search(text, token, limit)) {
    if (best === null || match.errors < best.errors) {
      best = match
    }
  }
  // A swap is itself one edit, so the variants only get what's left of the
  // budget. Without that the swap would be free and a four letter token would
  // effectively be allowed two typos rather than one.
  const swapLimit = limit - 1
  for (const candidate of swapLimit >= 0 ? swapVariants(token) : []) {
    if (best !== null && best.errors <= 1) {
      // Nothing a variant finds can beat the swap's own cost
      break
    }
    for (const match of search(text, candidate, swapLimit)) {
      const errors = match.errors + 1
      if (best === null || errors < best.errors) {
        best = { ...match, errors }
      }
    }
  }
  if (best === null) {
    return null
  }
  return { distance: best.errors, start: best.start, end: best.end }
}

// highlightResult() slices the value using each range in order, so the ranges
// have to be ascending and non-overlapping. Tokens match in query order
// ("stat heal" against HEALTH_STATUS gives [[7, 11], [0, 4]]) and can overlap
// each other, so sort and merge before handing them over.
const mergeRanges = function (ranges) {
  ranges.sort((a, b) => a[0] - b[0] || a[1] - b[1])
  const merged = []
  for (const range of ranges) {
    const last = merged.at(-1)
    if (last && range[0] <= last[1]) {
      last[1] = Math.max(last[1], range[1])
    } else {
      merged.push([...range])
    }
  }
  return merged
}

// Every place token appears in text, as [start, end) ranges
const allOccurrences = function (text, token) {
  const found = []
  let index = text.indexOf(token)
  while (index !== -1) {
    found.push([index, index + token.length])
    index = text.indexOf(token, index + token.length)
  }
  return found
}

// Match query against value, returning null if any token is missing. The
// result carries what's needed both to highlight the match (ranges) and to
// rank it against other matches (distance, the total number of typos, and
// index, where the match starts).
const tokenizedMatch = function (value, query) {
  if (value == null || query == null) {
    return null
  }
  const tokens = String(query).toLowerCase().split(/\s+/).filter(Boolean)
  if (tokens.length === 0) {
    // Whitespace only, so match everything with nothing highlighted
    return { ranges: [], distance: 0, index: 0 }
  }

  const text = String(value).toLowerCase()
  const ranges = []
  let distance = 0
  for (const token of tokens) {
    // Highlight every occurrence, which is what the built-in filter does
    const exact = allOccurrences(text, token)
    if (exact.length) {
      ranges.push(...exact)
      continue
    }
    // Nothing exact, so allow the token to have been mistyped
    const limit = maxEdits(token.length)
    const fuzzy = limit > 0 ? fuzzyIndexOf(text, token, limit) : null
    if (fuzzy === null) {
      // Every token has to match
      return null
    }
    ranges.push([fuzzy.start, fuzzy.end])
    distance += fuzzy.distance
  }

  const merged = mergeRanges(ranges)
  return {
    ranges: merged,
    distance,
    index: merged.length ? merged[0][0] : 0,
  }
}

// Vuetify FilterFunction: -1 for no match, or the ranges to highlight
const tokenizedFilter = function (value, query) {
  const match = tokenizedMatch(value, query)
  if (match === null) {
    return false
  }
  // No ranges means the query was whitespace only: everything matches, with
  // nothing to highlight
  return match.ranges.length ? match.ranges : true
}

// Sort items so the closest matches come first, which matters because
// auto-select-first means whatever lands on top is what Enter picks. Exact
// matches sort above typo matches, earlier matches above later ones, and
// anything else keeps the order it came in with. key names the property on
// each item holding the text to match.
const tokenizedSort = function (items, query, key) {
  if (!query?.trim()) {
    return items
  }
  return items
    .map((item, index) => ({
      item,
      index,
      match: tokenizedMatch(item[key], query),
    }))
    .sort((a, b) => {
      if (a.match === null || b.match === null) {
        if (a.match === b.match) return a.index - b.index
        return a.match === null ? 1 : -1
      }
      return (
        a.match.distance - b.match.distance ||
        a.match.index - b.match.index ||
        a.index - b.index
      )
    })
    .map((ranked) => ranked.item)
}

export { tokenizedFilter, tokenizedMatch, tokenizedSort }
