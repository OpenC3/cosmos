const utils = {
  mergeKeyWithParent(object, property) {
    if (object[property] === undefined) {
      return object;
    }
    if (typeof object[property] !== 'object') {
      return object;
    }
    const newObject = Object.assign({}, object, object[property]);
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
      if (!Object.prototype.hasOwnProperty.call(newCollection, key)) {
        newCollection[key] = [];
      }
      newCollection[key].push(item);
    });
    return newCollection;
  },

  values(object) {
    return Object.keys(object).map(key => object[key]);
  },

  flatten(array) {
    const results = [];
    array.forEach(value => {
      if (!Array.isArray(value)) {
        results.push(value);
        return;
      }
      value.forEach(subvalue => {
        results.push(subvalue);
      });
    });
    return results;
  },

  flattenAndFlagFirst(object, flag) {
    const values = this.values(object).map(collection =>
      collection.map((item, index) => {
        item[flag] = index === 0;
        return item;
      })
    );
    return this.flatten(values);
  },

  compact(array) {
    const results = [];
    array.forEach(value => {
      if (!value) {
        return;
      }
      results.push(value);
    });
    return results;
  },

  getHighlightedValue(object, property) {
    const hierarchyEntry = object._highlightResult?.hierarchy_camel?.[property];
    if (
      hierarchyEntry?.matchLevel &&
      hierarchyEntry.matchLevel !== 'none' &&
      hierarchyEntry.value
    ) {
      return hierarchyEntry.value;
    }
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

  deepClone(object) {
    return JSON.parse(JSON.stringify(object));
  },
};

export default utils;
