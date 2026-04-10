/*
Search Adapter using MiniSearch
*/

import MiniSearch from "@generated/mini-search.client";

class MiniSearchAdapter {
    constructor(searchDocs, searchIndex, maxHits) {
        this.searchDocs = searchDocs;
        this.miniSearch = MiniSearch.loadJSON(JSON.stringify(searchIndex), {
            idField: "id",
            fields: ["title", "content", "keywords"],
            storeFields: ["title", "content", "keywords"],
            searchOptions: {
                prefix: true,
            },
        });
        this.maxHits = maxHits;
    }

    // Find the first case-insensitive occurrence of any search term in text
    findTermPosition(text, terms) {
        if (!text) return null;
        const lowerText = text.toLowerCase();
        for (const term of terms) {
            const idx = lowerText.indexOf(term.toLowerCase());
            if (idx !== -1) {
                return [idx, term.length];
            }
        }
        return null;
    }

    getHit(doc, formattedTitle, formattedContent) {
        return {
            hierarchy: {
                lvl0: doc.pageTitle || doc.title,
                lvl1: doc.type === 0 ? null : doc.title
            },
            url: doc.url,
            version: doc.version,
            _snippetResult: formattedContent ? {
                content: {
                    value: formattedContent,
                    matchLevel: "full"
                }
            } : null,
            _highlightResult: {
                hierarchy: {
                    lvl0: {
                        value: doc.type === 0 ? formattedTitle || doc.title : doc.pageTitle,
                    },
                    lvl1:
                        doc.type === 0
                            ? null
                            : {
                                value: formattedTitle || doc.title
                            }
                }
            }
        };
    }

    getTitleHit(doc, position, length) {
        const start = position[0];
        const end = position[0] + length;
        let formattedTitle = doc.title.substring(0, start) + '<span class="algolia-docsearch-suggestion--highlight">' + doc.title.substring(start, end) + '</span>' + doc.title.substring(end, doc.title.length);
        return this.getHit(doc, formattedTitle)
    }

    getKeywordHit(doc, position, length) {
        const start = position[0];
        const end = position[0] + length;
        let formattedTitle = doc.title + '<br /><i>Keywords: ' + doc.keywords.substring(0, start) + '<span class="algolia-docsearch-suggestion--highlight">' + doc.keywords.substring(start, end) + '</span>' + doc.keywords.substring(end, doc.keywords.length) + '</i>'
        return this.getHit(doc, formattedTitle)
    }

    getContentHit(doc, position) {
        const start = position[0];
        const end = position[0] + position[1];
        let previewStart = start;
        let previewEnd = end;
        let ellipsesBefore = true;
        let ellipsesAfter = true;
        for (let k = 0; k < 3; k++) {
            const nextSpace = doc.content.lastIndexOf(' ', previewStart - 2);
            const nextDot = doc.content.lastIndexOf('.', previewStart - 2);
            if ((nextDot > 0) && (nextDot > nextSpace)) {
                previewStart = nextDot + 1;
                ellipsesBefore = false;
                break;
            }
            if (nextSpace < 0) {
                previewStart = 0;
                ellipsesBefore = false;
                break;
            }
            previewStart = nextSpace + 1;
        }
        for (let k = 0; k < 10; k++) {
            const nextSpace = doc.content.indexOf(' ', previewEnd + 1);
            const nextDot = doc.content.indexOf('.', previewEnd + 1);
            if ((nextDot > 0) && (nextDot < nextSpace)) {
                previewEnd = nextDot;
                ellipsesAfter = false;
                break;
            }
            if (nextSpace < 0) {
                previewEnd = doc.content.length;
                ellipsesAfter = false;
                break;
            }
            previewEnd = nextSpace;
        }
        let preview = doc.content.substring(previewStart, start);
        if (ellipsesBefore) {
            preview = '... ' + preview;
        }
        preview += '<span class="algolia-docsearch-suggestion--highlight">' + doc.content.substring(start, end) + '</span>';
        preview += doc.content.substring(end, previewEnd);
        if (ellipsesAfter) {
            preview += ' ...';
        }
        return this.getHit(doc, null, preview);
    }

    search(input) {
        return new Promise((resolve) => {
            const results = this.miniSearch.search(input, {
                boost: { title: 10 },
                prefix: true,
            });
            const hits = [];
            const truncated = results.slice(0, this.maxHits);
            const titleHitsRef = new Set();

            for (const result of truncated) {
                const doc = this.searchDocs[result.id];
                if (!doc) continue;
                const terms = result.terms;

                // Check title match
                const titlePos = this.findTermPosition(doc.title, terms);
                if (titlePos && !titleHitsRef.has(result.id)) {
                    hits.push(this.getTitleHit(doc, titlePos, input.length));
                    titleHitsRef.add(result.id);
                    continue;
                }

                // Check keywords match
                const keywordPos = this.findTermPosition(doc.keywords, terms);
                if (keywordPos && !titleHitsRef.has(result.id)) {
                    hits.push(this.getKeywordHit(doc, keywordPos, input.length));
                    titleHitsRef.add(result.id);
                    continue;
                }

                // Check content match
                const contentPos = this.findTermPosition(doc.content, terms);
                if (contentPos) {
                    hits.push(this.getContentHit(doc, contentPos));
                }
            }

            hits.length > this.maxHits && (hits.length = this.maxHits);
            resolve(hits);
        });
    }
}

export default MiniSearchAdapter;
