import React, { useRef, useCallback, useState, useEffect } from "react";
import clsx from "clsx";
import { useHistory } from "@docusaurus/router";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import { usePluginData } from "@docusaurus/useGlobalData";
import useIsBrowser from "@docusaurus/useIsBrowser";
import { HighlightSearchResults } from "./HighlightSearchResults";
const Search = ({
  handleSearchBarToggle = undefined,
  isSearchBarExpanded = false,
  autoFocus = false,
}) => {
  const initialized = useRef(false);
  const mountedRef = useRef(true);
  const docSearchRef = useRef(null);
  const searchBarRef = useRef(null);
  const [indexReady, setIndexReady] = useState(false);
  const history = useHistory();
  const { siteConfig = {} } = useDocusaurusContext();
  const pluginConfig = (siteConfig.plugins || []).find(
    (plugin) =>
      Array.isArray(plugin) &&
      typeof plugin[0] === "string" &&
      plugin[0].includes("docusaurus-search"),
  );
  const isBrowser = useIsBrowser();
  const { baseUrl } = siteConfig;
  const assetUrl = pluginConfig?.[1]?.assetUrl || baseUrl;
  const initAlgolia = (searchDocs, searchIndex, DocSearch, options) => {
    docSearchRef.current = new DocSearch({
      searchDocs,
      searchIndex,
      baseUrl,
      inputSelector: "#search_input_react",
      // Override algolia's default selection event, allowing us to do client-side
      // navigation and avoiding a full page refresh.
      handleSelected: (_input, _event, suggestion) => {
        const url = suggestion.url || "/";
        // Use an anchor tag to parse the absolute url into a relative url
        // Alternatively, we can use new URL(suggestion.url) but its not supported in IE
        const a = document.createElement("a");
        a.href = url;
        _input.setVal(""); // clear value
        _event.target.blur(); // remove focus

        // Get the highlight word from the suggestion.
        let wordToHighlight = "";
        if (options.highlightResult) {
          try {
            const matchedLine =
              suggestion.text || suggestion.subcategory || suggestion.title;
            const matchedWordResult = matchedLine.match(
              /<span.+span>\w*/g,
            );
            if (matchedWordResult && matchedWordResult.length > 0) {
              const parsed = new DOMParser().parseFromString(matchedWordResult[0], "text/html");
              wordToHighlight = parsed.body.textContent;
            }
          } catch (e) {
            console.log(e);
          }
        }

        history.push(url, {
          highlightState: { wordToHighlight },
        });
      },
      maxHits: options.maxHits,
    });
  };

  const pluginData = usePluginData("docusaurus-search");
  const getSearchDoc = () =>
    process.env.NODE_ENV === "production"
      ? fetch(`${assetUrl}${pluginData.fileNames.searchDoc}`).then((content) =>
          content.json(),
        )
      : Promise.resolve({});

  const getLunrIndex = () =>
    process.env.NODE_ENV === "production"
      ? fetch(`${assetUrl}${pluginData.fileNames.lunrIndex}`).then((content) =>
          content.json(),
        )
      : Promise.resolve([]);

  const loadAlgolia = () => {
    if (!initialized.current) {
      initialized.current = true;
      Promise.all([
        getSearchDoc(),
        getLunrIndex(),
        import("./DocSearch"),
        import("./algolia.css"),
      ]).then(([searchDocFile, searchIndex, { default: DocSearch }]) => {
        if (!mountedRef.current) return;
        const { searchDocs, options } = searchDocFile;
        if (!searchDocs || searchDocs.length === 0) {
          return;
        }
        initAlgolia(searchDocs, searchIndex, DocSearch, options);
        setIndexReady(true);
      }).catch((err) => {
        console.error("docusaurus-search: failed to load search index", err);
        initialized.current = false;
      });
    }
  };

  const toggleSearchIconClick = useCallback(
    (e) => {
      if (!searchBarRef.current.contains(e.target)) {
        searchBarRef.current.focus();
      }

      handleSearchBarToggle?.(!isSearchBarExpanded);
    },
    [isSearchBarExpanded, handleSearchBarToggle],
  );

  let placeholder;
  if (isBrowser) {
    loadAlgolia();
    placeholder = globalThis.navigator.userAgentData?.platform === "macOS" || /Mac/.test(globalThis.navigator.userAgent)
      ? "Search ⌘+K"
      : "Search Ctrl+K";
  }

  useEffect(() => {
    return () => {
      mountedRef.current = false;
      docSearchRef.current?.destroy();
    };
  }, []);

  // auto focus search bar on page load
  useEffect(() => {
    if (autoFocus && indexReady) {
      searchBarRef.current.focus();
    }
  }, [indexReady]);

  return (
    <div className="navbar__search" key="search-box">
      <span
        aria-label="expand searchbar"
        role="button"
        className={clsx("search-icon", {
          "search-icon-hidden": isSearchBarExpanded,
        })}
        onClick={toggleSearchIconClick}
        onKeyDown={toggleSearchIconClick}
        tabIndex={0}
      />
      <input
        id="search_input_react"
        type="search"
        placeholder={indexReady ? placeholder : "Loading..."}
        aria-label="Search"
        className={clsx(
          "navbar__search-input",
          { "search-bar-expanded": isSearchBarExpanded },
          { "search-bar": !isSearchBarExpanded },
        )}
        onClick={loadAlgolia}
        onMouseOver={loadAlgolia}
        onFocus={toggleSearchIconClick}
        onBlur={toggleSearchIconClick}
        ref={searchBarRef}
        disabled={!indexReady}
      />
      <HighlightSearchResults />
    </div>
  );
};

export default Search;
