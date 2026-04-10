import { parentPort, workerData } from "node:worker_threads";
import fs from "node:fs";
import * as cheerio from "cheerio";

/**
 * Finds the first <article> element that contains a .markdown child.
 * Docusaurus renders doc content inside <article><div class="markdown">...</div></article>.
 * @param {CheerioAPI} $$ - Cheerio instance loaded with the page HTML
 * @returns {[Cheerio|null, Cheerio|null]} Tuple of [markdownDiv, articleElement], or [null, null] if not found
 */
function findArticleWithMarkdown($$) {
  const articles = $$("article");
  for (const el of articles) {
    const article = $$(el);
    const markdown = article.find(".markdown");
    if (markdown.length) {
      return [markdown, article];
    }
  }
  return [null, null];
}

/**
 * Generator that parses a built HTML file and yields search documents.
 * Yields one document for the page title (type 0), then one document per
 * section heading h2/h3/h4 (type 1) with the content between that heading
 * and the next.
 * @param {Object} file
 * @param {string} file.path - Absolute path to the HTML file
 * @param {string} file.url - The route URL for this page
 * @yields {Object} Search document with title, type, url, content, keywords, and version
 */
function* scanDocuments({ path, url }) {
  let html;
  try {
    html = fs.readFileSync(path, "utf-8");
  } catch (e) {
    if (e.code !== "ENOENT") {
      console.error(`docusaurus-search:: unable to read file ${path}`);
      console.error(e);
    }
    return;
  }

  const $$ = cheerio.load(html);

  const [markdown, article] = findArticleWithMarkdown($$);
  if (!markdown) {
    return;
  }

  const pageTitleElement = article.find("h1").first();
  if (!pageTitleElement.length) {
    return;
  }
  const pageTitle = pageTitleElement.text();
  const sectionHeaders = getSectionHeaders(markdown, $$);

  const keywords = $$('meta[name="keywords"]')
    .toArray()
    .reduce((acc, el) => {
      const content = $$(el).attr("content");
      if (content) {
        return acc.concat(content.replaceAll(",", " "));
      }
      return acc;
    }, [])
    .join(" ");

  let version = null;
  if (workerData.loadedVersions) {
    const versionMeta = $$('meta[name="docsearch:version"]');
    version = versionMeta.length
      ? workerData.loadedVersions[versionMeta.attr("content")]
      : null;
  }

  yield {
    title: pageTitle,
    type: 0,
    sectionRef: "#",
    url,
    // If there is no sections then push the complete content under page title
    content: sectionHeaders.length === 0 ? getContent(markdown) : "",
    keywords,
    version,
  };

  for (const sectionDesc of sectionHeaders) {
    const { title, content, ref, tagName } = sectionDesc;
    yield {
      title,
      type: 1,
      pageTitle,
      url: `${url}#${ref}`,
      content,
      version,
      tagName,
    };
  }
}

const WHITESPACE_RE = /\s\s+/g;
const NEWLINE_RE = /(\r\n|\n|\r)/gm;

/**
 * Extracts and sanitizes text content from a Cheerio element or string.
 * Collapses whitespace, removes newlines, and HTML-encodes special characters.
 * @param {Cheerio|string} el - A Cheerio element or raw string
 * @returns {string} Cleaned, HTML-safe text content
 */
function getContent(el) {
  const text = typeof el === "string" ? el : el.text();
  return text
    .replaceAll(WHITESPACE_RE, " ")
    .replaceAll(NEWLINE_RE, " ")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/**
 * Walks the markdown content tree and extracts section headings (h2-h4) with
 * their associated content. Each heading becomes a section document with the
 * text between it and the next heading as its content.
 * @param {Cheerio} markdown - The .markdown container element
 * @param {CheerioAPI} $$ - Cheerio instance for creating wrapped elements
 * @returns {Array<{title: string, ref: string, tagName: string, content: string}>} Section descriptors
 */
function getSectionHeaders(markdown, $$) {
  const headerDocs = [];

  function traverse(el, isIndexingChildren = false, searchDoc = null) {
    el.children().each((_, child) => {
      const node = $$(child);
      const tagName = child.tagName;

      if (tagName === "h2" || tagName === "h3" || tagName === "h4") {
        // Track heading — the id may be on the heading itself or on a child .anchor
        const headingId = node.attr("id");
        const childAnchor = node.find(".anchor");
        searchDoc = {
          title: node.text().replace(/^#+/, "").replace(/#$/, ""),
          ref: headingId || (childAnchor.length ? childAnchor.attr("id") : "#"),
          tagName: tagName || "#",
          content: "",
        };
        headerDocs.push(searchDoc);
      } else if (
        child.attribs?.["data-search-children"] !== undefined
      ) {
        traverse(node, true, searchDoc);
      } else if (
        isIndexingChildren &&
        child.children?.length &&
        tagName !== "p"
      ) {
        traverse(node, true, searchDoc);
      } else if (searchDoc) {
        searchDoc.content += `${getContent(node)} `;
      }
    });
  }

  traverse(markdown);
  return headerDocs;
}

/**
 * Processes a single HTML file by scanning it for search documents and sending
 * each document back to the parent thread. Sends a final message with the count
 * of documents found (0 or 1) to signal completion.
 * @param {Object} file - File descriptor with path and url properties
 */
function processFile(file) {
  let scanned = 0;
  for (const doc of scanDocuments(file)) {
    scanned = 1;
    parentPort.postMessage([true, doc]);
  }
  parentPort.postMessage([null, scanned]);
}

parentPort.on("message", (maybeFile) => {
  if (maybeFile) {
    processFile(maybeFile);
  } else {
    parentPort.close();
  }
});
