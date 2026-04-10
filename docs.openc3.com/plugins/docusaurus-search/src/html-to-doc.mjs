import { parentPort, workerData } from "node:worker_threads";
import fs from "node:fs";
import * as cheerio from "cheerio";

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

// Build search data for a html
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
