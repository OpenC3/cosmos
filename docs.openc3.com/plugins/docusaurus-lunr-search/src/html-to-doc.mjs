import { parentPort, workerData } from 'worker_threads'
import fs from 'fs'
import * as cheerio from 'cheerio'

function findArticleWithMarkdown($$) {
  const articles = $$('article')
  for (let i = 0; i < articles.length; i++) {
    const article = $$(articles[i])
    const markdown = article.find('.markdown')
    if (markdown.length) {
      return [markdown, article]
    }
  }
  return [null, null]
}

// Build search data for a html
function* scanDocuments({ path, url }) {
  let html
  try {
    html = fs.readFileSync(path, 'utf-8')
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error(`docusaurus-lunr-search:: unable to read file ${path}`)
      console.error(e)
    }
    return
  }

  const $$ = cheerio.load(html)

  const [markdown, article] = findArticleWithMarkdown($$)
  if (!markdown) {
    return
  }

  const pageTitleElement = article.find('h1').first()
  if (!pageTitleElement.length) {
    return
  }
  const pageTitle = pageTitleElement.text()
  const sectionHeaders = getSectionHeaders(markdown, $$)

  const keywords = $$('meta[name="keywords"]')
    .toArray()
    .reduce((acc, el) => {
      const content = $$(el).attr('content')
      if (content) {
        return acc.concat(content.replace(/,/g, ' '))
      }
      return acc
    }, [])
    .join(' ')

  let version = null
  if (workerData.loadedVersions) {
    const versionMeta = $$('meta[name="docsearch:version"]')
    version = versionMeta.length
      ? workerData.loadedVersions[versionMeta.attr('content')]
      : null
  }

  yield {
    title: pageTitle,
    type: 0,
    sectionRef: '#',
    url,
    // If there is no sections then push the complete content under page title
    content: sectionHeaders.length === 0 ? getContent(markdown) : '',
    keywords,
    version
  }

  for (const sectionDesc of sectionHeaders) {
    const { title, content, ref, tagName } = sectionDesc
    yield {
      title,
      type: 1,
      pageTitle,
      url: `${url}#${ref}`,
      content,
      version,
      tagName
    }
  }
}

function getContent(el) {
  const text = typeof el === 'string' ? el : el.text()
  return text
    .replace(/\s\s+/g, ' ')
    .replace(/(\r\n|\n|\r)/gm, ' ')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function getSectionHeaders(markdown, $$) {
  const headerDocs = []

  function traverse(el, isIndexingChildren = false, searchDoc = null) {
    el.children().each((_, child) => {
      const node = $$(child)
      const tagName = child.tagName

      if (tagName === 'h2' || tagName === 'h3') {
        // Track heading
        const anchor = node.find('.anchor')
        searchDoc = {
          title: node.text().replace(/^#+/, '').replace(/#$/, ''),
          ref: anchor.length ? anchor.attr('id') : '#',
          tagName: tagName || '#',
          content: ''
        }
        headerDocs.push(searchDoc)
      } else if (child.attribs && child.attribs['data-search-children'] !== undefined) {
        traverse(node, true, searchDoc)
      } else if (isIndexingChildren && child.children && child.children.length && tagName !== 'p') {
        traverse(node, true, searchDoc)
      } else if (searchDoc) {
        searchDoc.content += `${getContent(node)} `
      }
    })
  }

  traverse(markdown)
  return headerDocs
}

function processFile(file) {
  let scanned = 0
  for (const doc of scanDocuments(file)) {
    scanned = 1
    parentPort.postMessage([true, doc])
  }
  parentPort.postMessage([null, scanned])
}

parentPort.on('message', (maybeFile) => {
  if (maybeFile) {
    processFile(maybeFile)
  } else {
    parentPort.close()
  }
})
