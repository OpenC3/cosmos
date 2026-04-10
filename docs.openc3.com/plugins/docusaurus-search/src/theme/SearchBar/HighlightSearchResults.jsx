//copied from https://github.com/cmfcmf/docusaurus-search-local
import { useEffect, useState } from "react";
import { useLocation, useHistory } from "@docusaurus/router";

function highlightTextNodes(root, word) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const matches = [];
  const lower = word.toLowerCase();

  while (walker.nextNode()) {
    const node = walker.currentNode;
    // Skip script/style content
    const tag = node.parentElement?.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'MARK') continue;

    let idx = node.textContent.toLowerCase().indexOf(lower);
    while (idx !== -1) {
      matches.push({ node, index: idx });
      idx = node.textContent.toLowerCase().indexOf(lower, idx + lower.length);
    }
  }

  // Process in reverse so earlier splits don't shift later indices
  for (let i = matches.length - 1; i >= 0; i--) {
    const { node, index } = matches[i];
    const mark = document.createElement('mark');
    const highlighted = node.splitText(index);
    highlighted.splitText(word.length);
    mark.appendChild(highlighted.cloneNode(true));
    highlighted.parentNode.replaceChild(mark, highlighted);
  }
}

function removeHighlights(root) {
  root.querySelectorAll('mark').forEach(mark => {
    const parent = mark.parentNode;
    while (mark.firstChild) {
      parent.insertBefore(mark.firstChild, mark);
    }
    mark.remove();
    parent.normalize();
  });
}

export function HighlightSearchResults() {
  const location = useLocation();
  const history = useHistory();

  const [highlightData, setHighlightData] = useState({ wordToHighlight: '' });

  useEffect(() => {
    if (
      !location.state?.highlightState ||
      location.state.highlightState.wordToHighlight.length === 0
    ) {
      return;
    }
    setHighlightData(location.state.highlightState);

    const { highlightState, ...state } = location.state;
    history.replace({
      ...location,
      state,
    });
  }, [location.state?.highlightState, history, location]);

  useEffect(() => {
    if (highlightData.wordToHighlight.length === 0) {
      return;
    }

    // Make sure to also adjust parse.js if you change the top element here.
    const root =  document.getElementsByTagName("article")[0] ?? document.getElementsByTagName("main")[0] ;
    if (!root) {
      return;
    }

    highlightTextNodes(root, highlightData.wordToHighlight);
    return () => removeHighlights(root);
  }, [highlightData]);

  return null;
}
