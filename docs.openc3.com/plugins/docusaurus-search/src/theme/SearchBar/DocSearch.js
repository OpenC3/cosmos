import Hogan from "./mini-mustache";
import LunrSearchAdapter from "./lunar-search";
import templates from "./templates";
import utils from "./utils";

class DocSearch {
    constructor({
        searchDocs,
        searchIndex,
        inputSelector,
        debug = false,
        baseUrl = '/',
        queryDataCallback = null,
        transformData = false,
        queryHook = false,
        handleSelected = false,
        enhancedSearchInput = false,
        layout = "column",
        maxHits = 5
    }) {
        this.input = document.querySelector(inputSelector);
        if (!this.input) return;

        this.queryDataCallback = queryDataCallback || null;
        this.isSimpleLayout = layout === "simple";
        this.client = new LunrSearchAdapter(searchDocs, searchIndex, maxHits, baseUrl);
        this.transformData = transformData;
        this.queryHook = queryHook;
        this.customHandleSelected = handleSelected;
        this.cursorIndex = -1;
        this.suggestions = [];
        this.isOpen = false;

        this._buildDropdown();
        this._bindEvents();

        // Ctrl/Cmd + K to focus
        document.addEventListener('keydown', (e) => {
            if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
                this.input.focus();
                e.preventDefault();
            }
        });
    }

    _buildDropdown() {
        // Use the existing parent as the positioning wrapper instead of
        // re-parenting the input (which disrupts the navbar flex layout).
        this.wrapper = this.input.parentNode;
        this.wrapper.classList.add('algolia-autocomplete');
        this.wrapper.style.position = 'relative';

        // Create dropdown
        this.dropdown = document.createElement('div');
        this.dropdown.className = 'ds-dropdown-menu';
        this.dropdown.style.display = 'none';
        this.dropdown.innerHTML = '<div class="ds-dataset-1"><div class="ds-suggestions"></div></div>';
        this.wrapper.appendChild(this.dropdown);

        this.suggestionsContainer = this.dropdown.querySelector('.ds-suggestions');
    }

    _bindEvents() {
        let debounceTimer;
        this.input.addEventListener('input', () => {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => this._onInput(), 100);
        });

        this.input.addEventListener('keydown', (e) => this._onKeyDown(e));

        // Close on outside click
        document.addEventListener('click', (e) => {
            if (!this.wrapper.contains(e.target)) {
                this._close();
            }
        });

        // Close on escape
        this.input.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this._close();
                this.input.blur();
            }
        });
    }

    _onInput() {
        let query = this.input.value;
        if (!query || query.length < 1) {
            this._close();
            return;
        }

        if (this.queryHook) {
            query = this.queryHook(query) || query;
        }

        this.client.search(query).then(hits => {
            if (this.queryDataCallback && typeof this.queryDataCallback === "function") {
                this.queryDataCallback(hits);
            }
            if (this.transformData) {
                hits = this.transformData(hits) || hits;
            }
            const formatted = DocSearch.formatHits(hits);
            this._renderSuggestions(formatted);
        });
    }

    _renderSuggestions(hits) {
        this.suggestions = hits;
        this.cursorIndex = -1;

        if (!hits || hits.length === 0) {
            const emptyTemplate = Hogan.compile(templates.empty);
            this.suggestionsContainer.innerHTML = emptyTemplate.render({
                query: this.input.value
            });
            this._open();
            return;
        }

        const suggestionTemplate = this.isSimpleLayout
            ? templates.suggestionSimple
            : templates.suggestion;
        const template = Hogan.compile(suggestionTemplate);

        this.suggestionsContainer.innerHTML = hits
            .map((hit, i) =>
                `<div class="ds-suggestion" data-index="${i}">${template.render(hit)}</div>`
            )
            .join('');

        // Add footer
        const existingFooter = this.dropdown.querySelector('.ds-dataset-1 .algolia-docsearch-footer');
        if (!existingFooter) {
            const dataset = this.dropdown.querySelector('.ds-dataset-1');
            dataset.insertAdjacentHTML('beforeend', templates.footer);
        }

        // Bind click events on suggestions
        this.suggestionsContainer.querySelectorAll('.ds-suggestion').forEach(el => {
            el.addEventListener('mousedown', (e) => {
                // mousedown fires before blur, so we can navigate
                const idx = Number.parseInt(el.dataset.index, 10);
                const suggestion = this.suggestions[idx];
                if (suggestion) {
                    this._selectSuggestion(suggestion, e, 'click');
                }
            });
        });

        this._open();
    }

    _open() {
        this.dropdown.style.display = '';
        this.isOpen = true;
        this._updateAlignment();
    }

    _close() {
        this.dropdown.style.display = 'none';
        this.isOpen = false;
        this.cursorIndex = -1;
        this._clearCursor();
    }

    _updateAlignment() {
        // Always right-align the dropdown to the search input
        this.wrapper.classList.add('algolia-autocomplete-right');
        this.wrapper.classList.remove('algolia-autocomplete-left');
    }

    _onKeyDown(e) {
        if (!this.isOpen) return;

        const items = this.suggestionsContainer.querySelectorAll('.ds-suggestion');
        if (!items.length) return;

        if (e.key === 'ArrowDown') {
            e.preventDefault();
            this.cursorIndex = Math.min(this.cursorIndex + 1, items.length - 1);
            this._updateCursor(items);
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            this.cursorIndex = Math.max(this.cursorIndex - 1, 0);
            this._updateCursor(items);
        } else if (e.key === 'Enter') {
            e.preventDefault();
            const idx = this.cursorIndex >= 0 ? this.cursorIndex : 0;
            const suggestion = this.suggestions[idx];
            if (suggestion) {
                this._selectSuggestion(suggestion, e, 'key');
            }
        }
    }

    _updateCursor(items) {
        this._clearCursor();
        if (this.cursorIndex >= 0 && items[this.cursorIndex]) {
            items[this.cursorIndex].classList.add('ds-cursor');
        }
    }

    _clearCursor() {
        this.suggestionsContainer.querySelectorAll('.ds-cursor').forEach(el => {
            el.classList.remove('ds-cursor');
        });
    }

    _selectSuggestion(suggestion, event, selectionMethod) {
        const inputWrapper = {
            setVal: (val) => { this.input.value = val; },
        };

        this._close();

        if (this.customHandleSelected) {
            this.customHandleSelected(inputWrapper, event, suggestion, 0, {
                selectionMethod
            });
            return;
        }

        // Default behavior
        if (selectionMethod === 'click') return;
        this.input.value = '';
        globalThis.location.assign(suggestion.url);
    }

    // Given a list of hits, reformat them for templates
    static formatHits(receivedHits) {
        const clonedHits = utils.deepClone(receivedHits);
        const hits = clonedHits.map(hit => {
            if (hit._highlightResult) {
                hit._highlightResult = utils.mergeKeyWithParent(
                    hit._highlightResult,
                    "hierarchy"
                );
            }
            return utils.mergeKeyWithParent(hit, "hierarchy");
        });

        let groupedHits = utils.groupBy(hits, "lvl0");
        Object.entries(groupedHits).forEach(([level, collection]) => {
            const groupedHitsByLvl1 = utils.groupBy(collection, "lvl1");
            const flattenedHits = utils.flattenAndFlagFirst(
                groupedHitsByLvl1,
                "isSubCategoryHeader"
            );
            groupedHits[level] = flattenedHits;
        });
        groupedHits = utils.flattenAndFlagFirst(groupedHits, "isCategoryHeader");

        return groupedHits.map(hit => {
            const url = DocSearch.formatURL(hit);
            const category = utils.getHighlightedValue(hit, "lvl0");
            const subcategory = utils.getHighlightedValue(hit, "lvl1") || category;
            const displayTitle = utils
                .compact([
                    utils.getHighlightedValue(hit, "lvl2") || subcategory,
                    utils.getHighlightedValue(hit, "lvl3"),
                    utils.getHighlightedValue(hit, "lvl4"),
                    utils.getHighlightedValue(hit, "lvl5"),
                    utils.getHighlightedValue(hit, "lvl6")
                ])
                .join(
                    '<span class="aa-suggestion-title-separator" aria-hidden="true"> › </span>'
                );
            const text = utils.getSnippetedValue(hit, "content");
            const isTextOrSubcategoryNonEmpty =
                (subcategory && subcategory !== "") ||
                (displayTitle && displayTitle !== "");
            const isLvl1EmptyOrDuplicate =
                !subcategory || subcategory === "" || subcategory === category;
            const isLvl2 =
                displayTitle && displayTitle !== "" && displayTitle !== subcategory;
            const isLvl1 =
                !isLvl2 &&
                (subcategory && subcategory !== "" && subcategory !== category);
            const isLvl0 = !isLvl1 && !isLvl2;
            const version = hit.version;

            return {
                isLvl0,
                isLvl1,
                isLvl2,
                isLvl1EmptyOrDuplicate,
                isCategoryHeader: hit.isCategoryHeader,
                isSubCategoryHeader: hit.isSubCategoryHeader,
                isTextOrSubcategoryNonEmpty,
                category,
                subcategory,
                title: displayTitle,
                text,
                url,
                version
            };
        });
    }

    static formatURL(hit) {
        const { url, anchor } = hit;
        if (url) {
            const containsAnchor = url.includes("#");
            if (containsAnchor) return url;
            else if (anchor) return `${hit.url}#${hit.anchor}`;
            return url;
        } else if (anchor) return `#${hit.anchor}`;
        console.warn("no anchor nor url for : ", JSON.stringify(hit));
        return null;
    }
}

export default DocSearch;
