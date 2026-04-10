const prefix = 'algolia-docsearch';
const suggestionPrefix = `${prefix}-suggestion`;

/* eslint-disable max-len */

const templates = {
  suggestion: `
  <a class="${suggestionPrefix}
    {{#isCategoryHeader}}${suggestionPrefix}__main{{/isCategoryHeader}}
    {{#isSubCategoryHeader}}${suggestionPrefix}__secondary{{/isSubCategoryHeader}}
    "
    aria-label="Link to the result"
    href="{{{url}}}"
    >
    <div class="${suggestionPrefix}--category-header">
        <span class="${suggestionPrefix}--category-header-lvl0">{{{category}}}</span>
    </div>
    <div class="${suggestionPrefix}--wrapper">
      <div class="${suggestionPrefix}--subcategory-column">
        <span class="${suggestionPrefix}--subcategory-column-text">{{{subcategory}}}</span>
      </div>
      {{#isTextOrSubcategoryNonEmpty}}
      <div class="${suggestionPrefix}--content">
        <div class="${suggestionPrefix}--subcategory-inline">{{{subcategory}}}</div>
        <div class="${suggestionPrefix}--title">{{{title}}}</div>
        {{#text}}<div class="${suggestionPrefix}--text">{{{text}}}</div>{{/text}}
        {{#version}}<div class="${suggestionPrefix}--version">{{version}}</div>{{/version}}
      </div>
      {{/isTextOrSubcategoryNonEmpty}}
    </div>
  </a>
  `,
  empty: `
  <div class="${suggestionPrefix}">
    <div class="${suggestionPrefix}--wrapper">
        <div class="${suggestionPrefix}--content ${suggestionPrefix}--no-results">
            <div class="${suggestionPrefix}--title">
                <div class="${suggestionPrefix}--text">
                    No results found for query <b>"{{query}}"</b>
                </div>
            </div>
        </div>
    </div>
  </div>
  `,
};

export default templates;
