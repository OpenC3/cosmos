const utils = {
  mergeKeyWithParent(object, property) {
    if (object[property] === undefined) {
      return object;
    }
    if (typeof object[property] !== 'object') {
      return object;
    }
    const newObject = { ...object, ...object[property] };
    delete newObject[property];
    return newObject;
  },

  groupBy(collection, property) {
    const newCollection = {};
    collection.forEach((item) => {
      if (item[property] === undefined) {
        throw new Error(`[groupBy]: Object has no key ${property}`);
      }
      let key = item[property];
      if (typeof key === 'string') {
        key = key.toLowerCase();
      }
      if (!Object.hasOwn(newCollection, key)) {
        newCollection[key] = [];
      }
      newCollection[key].push(item);
    });
    return newCollection;
  },

  flattenAndFlagFirst(object, flag) {
    return Object.values(object).flatMap(collection =>
      collection.map((item, index) => {
        item[flag] = index === 0;
        return item;
      })
    );
  },

  compact(array) {
    return array.filter(Boolean);
  },

  getHighlightedValue(object, property) {
    const highlightValue = object._highlightResult?.[property]?.value;
    if (highlightValue) {
      return highlightValue;
    }
    return object[property];
  },

  getSnippetedValue(object, property) {
    const snippetValue = object._snippetResult?.[property]?.value;
    if (!snippetValue) {
      return object[property];
    }
    let snippet = snippetValue;

    if (snippet[0] !== snippet[0].toUpperCase()) {
      snippet = `…${snippet}`;
    }
    if (!['.', '!', '?'].includes(snippet[snippet.length - 1])) {
      snippet = `${snippet}…`;
    }
    return snippet;
  },

};

export default utils;
