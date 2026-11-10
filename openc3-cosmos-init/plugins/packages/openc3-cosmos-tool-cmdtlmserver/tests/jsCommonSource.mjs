/* Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. */

// Node module resolve hook so unit tests use @openc3/js-common's source rather
// than its dist build, which doesn't exist until the package is built.
// Register it before importing code that uses js-common:
//   register('./jsCommonSource.mjs', import.meta.url)
const SOURCES = {
  '@openc3/js-common/utils': new URL(
    '../../openc3-js-common/src/utils/sharedResources.js',
    import.meta.url,
  ).href,
}

export function resolve(specifier, context, nextResolve) {
  if (SOURCES[specifier]) {
    return { url: SOURCES[specifier], shortCircuit: true }
  }
  return nextResolve(specifier, context)
}
