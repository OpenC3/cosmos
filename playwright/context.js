'use strict'
/*
 Copyright 2012-2015, Yahoo Inc.
 Copyrights licensed under the New BSD License. See the accompanying LICENSE file for terms.
 */
const fs = require('fs')
const path = require('path')
const FileWriter = require('./file-writer')
const XMLWriter = require('./xml-writer')
const tree = require('./tree')
const watermarks = require('./watermarks')
const SummarizerFactory = require('./summarizer-factory')

function defaultSourceLookup(filePath) {
  try {
    filePath = filePath.split(path.sep).join(path.posix.sep)
    // Remove any Windows drive letters
    filePath = filePath.replace('C:', '')
    filePath = filePath.replace(
      '/openc3',
      // This assumes you've checked out playwright at the same level as the openc3 project
      process.cwd().split(path.sep).join(path.posix.sep) +
        '/../openc3-cosmos-init',
    )
    if (
      filePath.includes('enterprise') ||
      filePath.includes('openc3-cosmos-tool-autonomic') ||
      filePath.includes('openc3-cosmos-tool-calendar') ||
      filePath.includes('openc3-cosmos-tool-cmdqueue') ||
      filePath.includes('openc3-cosmos-tool-cmdhistory') ||
      filePath.includes('openc3-cosmos-tool-systemhealth')
    ) {
      filePath = filePath.replace(
        '../openc3-cosmos-init',
        '../../cosmos-enterprise/openc3-cosmos-enterprise-init',
      )
    }

    // For some reason we get duplicate path portions like:
    // /openc3-init/plugins/openc3-tool-base/src/src/AppNav.vue
    // /openc3-init/plugins/openc3-tool-base/src/components/src/components/ClockFooter.vue
    // /openc3-init/plugins/packages/openc3-tool-dataviewer/src/tools/DataViewer/src/tools/DataViewer/DumpComponent.vue
    // So look look for those duplicate src patterns and replace them with a single copy
    const found = filePath.match(/(src\/.*)src/)
    if (found) {
      let re = new RegExp(`(${found[1]}){2}`)
      filePath = filePath.replace(re, '$1')
    }
    return fs.readFileSync(path.normalize(filePath), 'utf8')
  } catch (ex) {
    throw new Error(`Unable to lookup source: ${filePath} (${ex.message})`)
  }
}

function normalizeWatermarks(specified = {}) {
  Object.entries(watermarks.getDefault()).forEach(([k, value]) => {
    const specValue = specified[k]
    if (!Array.isArray(specValue) || specValue.length !== 2) {
      specified[k] = value
    }
  })

  return specified
}

/**
 * A reporting context that is passed to report implementations
 * @param {Object} [opts=null] opts options
 * @param {String} [opts.dir='coverage'] opts.dir the reporting directory
 * @param {Object} [opts.watermarks=null] opts.watermarks watermarks for
 *  statements, lines, branches and functions
 * @param {Function} [opts.sourceFinder=fsLookup] opts.sourceFinder a
 *  function that returns source code given a file path. Defaults to
 *  filesystem lookups based on path.
 * @constructor
 */
class Context {
  constructor(opts) {
    this.dir = opts.dir || 'coverage'
    this.watermarks = normalizeWatermarks(opts.watermarks)
    this.sourceFinder = opts.sourceFinder || defaultSourceLookup
    this._summarizerFactory = new SummarizerFactory(
      opts.coverageMap,
      opts.defaultSummarizer,
    )
    this.data = {}
  }

  /**
   * returns a FileWriter implementation for reporting use. Also available
   * as the `writer` property on the context.
   * @returns {Writer}
   */
  getWriter() {
    return this.writer
  }

  /**
   * returns the source code for the specified file path or throws if
   * the source could not be found.
   * @param {String} filePath the file path as found in a file coverage object
   * @returns {String} the source code
   */
  getSource(filePath) {
    return this.sourceFinder(filePath)
  }

  /**
   * returns the coverage class given a coverage
   * types and a percentage value.
   * @param {String} type - the coverage type, one of `statements`, `functions`,
   *  `branches`, or `lines`
   * @param {Number} value - the percentage value
   * @returns {String} one of `high`, `medium` or `low`
   */
  classForPercent(type, value) {
    const watermarks = this.watermarks[type]
    if (!watermarks) {
      return 'unknown'
    }
    if (value < watermarks[0]) {
      return 'low'
    }
    if (value >= watermarks[1]) {
      return 'high'
    }
    return 'medium'
  }

  /**
   * returns an XML writer for the supplied content writer
   * @param {ContentWriter} contentWriter the content writer to which the returned XML writer
   *  writes data
   * @returns {XMLWriter}
   */
  getXMLWriter(contentWriter) {
    return new XMLWriter(contentWriter)
  }

  /**
   * returns a full visitor given a partial one.
   * @param {Object} partialVisitor a partial visitor only having the functions of
   *  interest to the caller. These functions are called with a scope that is the
   *  supplied object.
   * @returns {Visitor}
   */
  getVisitor(partialVisitor) {
    return new tree.Visitor(partialVisitor)
  }

  getTree(name = 'defaultSummarizer') {
    return this._summarizerFactory[name]
  }
}

Object.defineProperty(Context.prototype, 'writer', {
  enumerable: true,
  get() {
    if (!this.data.writer) {
      this.data.writer = new FileWriter(this.dir)
    }
    return this.data.writer
  },
})

module.exports = Context
